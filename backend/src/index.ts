import { initializeApp } from 'firebase-admin/app';
import { getFirestore, FieldValue} from 'firebase-admin/firestore';
import { getAuth } from 'firebase-admin/auth';
import { onCall, HttpsError, onRequest } from 'firebase-functions/v2/https';
import { GoogleGenerativeAI } from '@google/generative-ai';
import { defineSecret } from 'firebase-functions/params';
import { AuthData } from 'firebase-functions/v2/tasks'; // Import AuthData type if needed elsewhere

// Define the Gemini API key secret with a different name to avoid conflicts
const geminiSecretKey = defineSecret('GEMINI_SECRET_KEY');

// Rule: Always add debug logs
console.log('🚀 Cloud Functions V2 initialized');

// Initialize Firebase Admin with application default credentials
// This is safer than using a service account key file
const app = initializeApp();
console.log('🔥 Firebase Admin initialized', { appName: app.name });

// Get Firestore instance
const db = getFirestore();
console.log('📊 Firestore initialized');

// Get Auth instance
const auth = getAuth();
console.log('🔑 Firebase Auth Admin initialized');

// --- Rate Limiting Constants ---
const IP_RATE_LIMIT_WINDOW_SECONDS = 60; // 1 minute
const IP_RATE_LIMIT_MAX_REQUESTS = 30; // Max requests per window per IP
// -----------------------------

interface ConversationData {
  messages: Array<{
    role: string;
    content: string;
    timestamp: any;
  }>;
  lastUpdated?: any;
  title?: string;
  chatMode?: string;
}

interface UserProfile {
  name?: string;
  age?: number;
  gender?: 'male' | 'female' | 'non_binary' | 'prefer_not_to_say';
  goals?: string[];
  intentions?: string[];
  preferredTone?: 'gentle' | 'direct' | 'motivational' | 'neutral';
  experienceLevel?: 'beginner' | 'intermediate' | 'advanced';
  sufferingDuration?: string;
  hasCompletedProfileSetup?: boolean;
}

async function getUserProfile(uid: string): Promise<UserProfile | null> {
  try {
    const doc = await db.collection('users').doc(uid).get();
    const data = doc.data();
    if (!data || !data.profile) return null;
    return data.profile as UserProfile;
  } catch (e) {
    console.error('[getUserProfile] Failed to fetch profile for', uid, e);
    return null;
  }
}

function buildUserContextPrompt(profile: UserProfile | null): string {
  if (!profile) return '';
  const parts: string[] = [];
  if (profile.name) parts.push(`User name: ${profile.name}`);
  if (typeof profile.age === 'number') parts.push(`User age: ${profile.age}`);
  if (profile.gender) parts.push(`Gender: ${profile.gender}`);
  if (profile.experienceLevel) parts.push(`Experience level: ${profile.experienceLevel}`);
  if (profile.preferredTone) parts.push(`Preferred tone: ${profile.preferredTone}`);
  if (profile.sufferingDuration) parts.push(`Suffering duration: ${profile.sufferingDuration}`);
  if (profile.goals && profile.goals.length) parts.push(`Goals: ${profile.goals.join(', ')}`);
  if (profile.intentions && profile.intentions.length) parts.push(`Intentions: ${profile.intentions.join(', ')}`);
  const header = 'Personalization Context: Use this information to tailor responses appropriately. Do not ask the user to repeat it unless necessary.';
  return [header, ...parts].filter(Boolean).join('\n');
}

const SYSTEM_PROMPTS = {
    task: `You are Calendo AI, a helpful digital assistant specializing in task management and productivity. Your role is to help users break down goals into actionable tasks and provide task management advice. Detect the user's language and respond in that language.

TASK MANAGEMENT APPROACH:
- Help users break down complex goals into manageable tasks
- Provide productivity coaching and task organization advice
- Focus on actionable steps and clear deliverables
- Guide users through task prioritization and planning

WHEN TO CREATE A TASK (TRIGGERS):
Create a task immediately when you understand ANY of these:
1. User mentions wanting to accomplish something specific
2. User asks for help organizing their work or projects
3. User expresses a goal that needs to be broken down into steps
4. User mentions having too much to do or feeling overwhelmed
5. User asks for help planning or organizing tasks

TASK CREATION PROCESS:
When you detect ANY of the above triggers, respond with your message AND include the flag [TASKGEN=True] at the end.

CRITICAL: You MUST include [TASKGEN=True] at the end of your response when creating tasks!

Example:
"Perfect! I'll help you break this down into manageable tasks. [TASKGEN=True]"

The system will then automatically generate a detailed task structure.

REMEMBER: Always end your response with [TASKGEN=True] when creating tasks!

CONVERSATION GUIDELINES:
- Be encouraging and solution-focused
- Help users prioritize and organize their work
- Break down complex projects into simple steps
- Provide productivity tips and task management advice
- Focus on actionable outcomes and clear next steps

EXAMPLES OF GOOD RESPONSES:
User: "I need to plan my vacation"
You: "Great! Let's break down your vacation planning into clear, manageable tasks. I'll create a step-by-step plan to make this process smooth and stress-free. [TASKGEN=True]"

User: "I'm overwhelmed with my work projects"
You: "I understand that feeling! Let's organize your projects into prioritized tasks so you can tackle them systematically. I'll help you create a clear action plan. [TASKGEN=True]"

User: "I want to study for my exam"
You: "Excellent! A structured study plan will help you succeed. I'll break down your exam preparation into focused study tasks. [TASKGEN=True]"

Remember: Your goal is to help users organize their work and break down goals into actionable tasks. Be decisive and action-oriented!

CRITICAL REMINDER: Always end your response with [TASKGEN=True] when creating tasks!`,

    habit: `You are Calendo AI, a helpful digital assistant specializing in habit formation. Your role is to quickly understand user goals and create comprehensive habit programs. Detect the user's language and respond in that language.

HABIT CREATION APPROACH:
- Be direct and action-oriented - create habits quickly based on user requests
- Make reasonable assumptions about frequency, timing, and approach
- Only ask 1-2 clarifying questions if absolutely necessary
- Focus on creating habits, not having long conversations

WHEN TO CREATE A HABIT (TRIGGERS):
Create a habit immediately when you understand ANY of these:
1. User mentions wanting to start/begin/learn a specific habit
2. User asks for help with a particular activity or behavior
3. User expresses a goal that can be achieved through a habit
4. User mentions wanting to improve something in their life
5. User asks about building consistency in any area

HABIT CREATION PROCESS:
When you detect ANY of the above triggers, respond with your message AND include the flag [HABITGEN=True] at the end.

CRITICAL: You MUST include [HABITGEN=True] at the end of your response when creating habits!

Example:
"Perfect! I'll create a comprehensive habit program for you. [HABITGEN=True]"

The system will then automatically generate a detailed habit JSON structure.

REMEMBER: Always end your response with [HABITGEN=True] when creating habits!

CONVERSATION GUIDELINES:
- Be encouraging but concise
- Make smart assumptions about timing and frequency
- Default to daily habits at 07:00 unless context suggests otherwise
- Default to 10-30 minute duration unless specified
- Create habits for beginners unless they mention experience
- Don't over-question - act on what you know

EXAMPLES OF GOOD RESPONSES:
User: "I want to start exercising"
You: "Excellent! Exercise will boost your energy and confidence. I'll create a progressive fitness program that starts gentle and builds your strength over 8 weeks. [HABITGEN=True]"

User: "Help me meditate daily"
You: "Meditation is one of the best habits for mental clarity and stress relief. I'll design a daily meditation program that starts with 10 minutes and gradually builds your practice. [HABITGEN=True]"

User: "I need to drink more water"
You: "Staying hydrated is so important for your health and energy! I'll create a simple daily water habit that makes hydration automatic. [HABITGEN=True]"

User: "I want to read more books"
You: "Reading daily is fantastic for personal growth and knowledge. I'll create a reading habit that fits into your schedule and builds consistency. [HABITGEN=True]"

Remember: Your goal is to quickly understand the user's intent and create comprehensive habit programs immediately. Be decisive and action-oriented!

CRITICAL REMINDER: Always end your response with [HABITGEN=True] when creating habits!`
};

function getSystemPrompt(chatMode: string): string {
    const validModes = ['task', 'habit'];
    if (!validModes.includes(chatMode)) {
        console.warn(`[getSystemPrompt] Invalid chat mode: ${chatMode}, defaulting to task`);
        return SYSTEM_PROMPTS.task;
    }
    return SYSTEM_PROMPTS[chatMode as keyof typeof SYSTEM_PROMPTS];
}

function shouldGenerateHabit(responseText: string): boolean {
    // Look for the explicit HABITGEN flag
    const habitGenFlag = /\[HABITGEN\s*=\s*True\]/i;
    return habitGenFlag.test(responseText);
}

function shouldGenerateTask(responseText: string): boolean {
    // Look for the explicit TASKGEN flag
    const taskGenFlag = /\[TASKGEN\s*=\s*True\]/i;
    return taskGenFlag.test(responseText);
}

function buildConversationContext(messages: any[], currentMessage: string, currentResponse: string): string {
    const conversationParts = [];
    
    // Add previous messages (last 10 to keep context manageable)
    const recentMessages = messages.slice(-10);
    for (const msg of recentMessages) {
        conversationParts.push(`${msg.role}: ${msg.content}`);
    }
    
    // Add current exchange
    conversationParts.push(`user: ${currentMessage}`);
    conversationParts.push(`assistant: ${currentResponse}`);
    
    return conversationParts.join('\n\n');
}

async function generateHabitJsonInternal(conversation: string): Promise<{success: boolean, habitJson?: any}> {
    try {
        console.log('[generateHabitJsonInternal] Starting habit JSON generation');
        
        // Initialize Gemini AI
        const genAI = new GoogleGenerativeAI(geminiSecretKey.value());
        const model = genAI.getGenerativeModel({ model: 'gemini-2.0-flash' });
        
        // System prompt for habit generation based on habit.json schema
        const systemPrompt = `You are a specialized AI agent for creating personalized habit plans. Your role is to analyze user conversations and generate comprehensive habit JSON structures that can be implemented in a habit tracking application.

## Core Requirements

### 1. Basic Habit Information
- **name**: Clear, concise habit name (2-4 words)
- **goal**: Specific, measurable goal statement
- **category**: Categorization (health, productivity, mindfulness, fitness, learning, etc.)
- **description**: Detailed explanation of what the habit involves
- **difficulty**: "beginner" | "intermediate" | "advanced" - Determined based on conversation and user experience. The difficulty is determined based on conversation, and later the app can create a new habit which is continued from the previous habit.

### 2. Milestones System
Milestones are located in **high_level_schedule.milestones** (NOT at root level).
Every habit must have at least 3 milestones:
- **Foundation milestone** (index 0): First part completion, understand the habit needs and get used to.
- **Building milestone** (index 1): Middle part completion, more success over habit
- **Mastery milestone** (index 2+): Last part completion, full mastery

Each milestone needs:
- **index**: Sequential number starting from 0
- **description**: What this milestone represents
- **completion_criteria**: One of "streak_of_days" | "streak_of_weeks" | "streak_of_months" | "percentage"
- **completion_criteria_point**: Number value for the criteria
- **reward_message**: Encouraging message when achieved

### 3. Schedule Types

**IMPORTANT**: Every habit must have BOTH low_level_schedule AND high_level_schedule:
- **Low-Level Schedule**: For repetitive, routine habits with indexed day/week/month content
- **High-Level Schedule**: Contains milestones and progressive structure

#### Low-Level Schedule Structure
**Required fields:**
- **span**: "day" | "week" | "month" | "year"
- **span_value**: number - The length of one repeating cycle in the span unit (e.g., 1 for daily, 2 for every 2 weeks, 4 for a 4-day rotation cycle)
  - For multi-day repeating cycles: span_value equals the number of days in the cycle (e.g., 4-day gym rotation = span_value:4)
  - For daily habits: span_value=1
  - For weekly habits: span_value=1 (one week per cycle)
- **habit_schedule**: number | null
- **habit_repeat_count**: number | null
- **program**: Array with indexed content for days, weeks, and months

**CRITICAL: Understanding habit_schedule and habit_repeat_count**

**habit_repeat_count**: 
- **Definition**: How many times the program cycle will repeat
- **Type**: number | null
- **If null**: The habit repeats infinitely (no end date)
- **If number**: The habit repeats exactly that many times
- **Example**: habit_repeat_count: 12 means the program repeats 12 times

**habit_schedule**:
- **Definition**: Total duration the habit will be running, measured in DAYS
- **Type**: number | null  
- **If null**: The habit runs infinitely (no end date)
- **If number**: The habit runs for exactly that many days
- **Calculation Formula**: habit_schedule = habit_repeat_count × span × span_value (converted to days)
  - For span="day": habit_schedule = habit_repeat_count × span_value × 1
  - For span="week": habit_schedule = habit_repeat_count × span_value × 7
  - For span="month": habit_schedule = habit_repeat_count × span_value × 30 (approximate)
  - For span="year": habit_schedule = habit_repeat_count × span_value × 365 (approximate)

**Duration Calculation Rules:**
1. **span × span_value** = duration of one repeating cycle (in the span unit)
   - Example: span="week", span_value=2 → one cycle = 2 weeks
2. **habit_repeat_count** = how many times the cycle repeats
   - If null: cycle repeats infinitely
   - If number: cycle repeats exactly that many times
3. **habit_schedule** = total duration in DAYS that the habit will run
   - Formula: habit_schedule = habit_repeat_count × span × span_value (converted to days)
   - If null: habit runs infinitely (no end date)
   - If number: habit runs for exactly that many days

**IMPORTANT Relationships:**
- When BOTH habit_repeat_count and habit_schedule are null → habit is INFINITE
- When habit_repeat_count is set → habit_schedule MUST be calculated using the formula above
- When habit_schedule is set → it represents the total duration in days regardless of habit_repeat_count
- For infinite habits → set both to null: habit_repeat_count: null, habit_schedule: null

**Examples:**
- Example 1: 2 weeks plan repeating for 6 months
  - span: "week", span_value: 2, habit_repeat_count: 12, habit_schedule: 168 (12 × 2 × 7 = 168 days)
- Example 2: Infinite daily habit (e.g., daily water intake)
  - span: "day", span_value: 1, habit_repeat_count: null, habit_schedule: null
- Example 3: 4-day gym rotation (chest, back, leg, rest) repeating indefinitely
  - span: "day", span_value: 4, habit_repeat_count: null, habit_schedule: null
- Example 4: 30-day program repeating 3 times
  - span: "day", span_value: 30, habit_repeat_count: 3, habit_schedule: 90 (3 × 30 × 1 = 90 days)

**Program Structure:**
Program has all the details in three contexts: days, weeks, months.
All three of days_indexed, weeks_indexed, months_indexed will have indexed elements which have details about the date.
On app's calendar view: days_indexed contents will be rendered on daily view, weeks_indexed content will be rendered on weekly view, months_indexed content will be rendered on monthly view.

Each program element must have:
- **days_indexed**: Array of day entries with:
  - **index**: Day number (CRITICAL: days_indexed starts with index 1, NOT 0. First day = index 1, second day = index 2, etc.)
  - **title**: Title for this day
  - **content**: Array of steps, each with:
    - **step**: String description of what to do
    - **clock**: "00:00" format time or null (if the step clock data is null it means anytime in day it can be done)
  - **reminders**: Array with:
    - **time**: "00:00" format or null
    - **message**: String or null
  - **USE days_indexed FOR**: Patterns that repeat every N days regardless of week boundaries (e.g., workout every 2 days, gym rotation every 4 days: chest→back→leg→rest). For a 4-day rotation, create 4 entries (index 1, 2, 3, 4) and set span="day", span_value=4.

- **weeks_indexed**: Array of week entries with:
  - **index**: Week number (CRITICAL: weeks_indexed starts with index 1, NOT 0. First week = index 1, second week = index 2, etc.)
  - **title**: Title for this week
  - **content**: Array of steps, each with:
    - **step**: String description
    - **day**: "Monday" | "Tuesday" | "Wednesday" | "Thursday" | "Friday" | "Saturday" | "Sunday"
  - **reminders**: Array with:
    - **time**: "00:00" format or null
    - **message**: String or null
  - **USE weeks_indexed FOR**: Patterns tied to specific days of the week (e.g., gym on Monday/Wednesday/Friday every week). Do NOT use weeks_indexed for multi-day cycles that repeat every N days.

- **months_indexed**: Array of month entries with:
  - **index**: Month number (CRITICAL: months_indexed starts with index 1, NOT 0. First month = index 1, second month = index 2, etc.)
  - **title**: Title for this month
  - **content**: Array of steps, each with:
    - **step**: String description (INCLUDE TIME IN STEP DESCRIPTION if user specifies a time, e.g., "Go to dinner at 20:00")
    - **day**: "start_of_month" | "1" | "2" | "3" | "4" | "5" | "6" | "7" | "8" | "9" | "10" | "11" | "12" | "13" | "14" | "15" | "16" | "17" | "18" | "19" | "20" | "21" | "22" | "23" | "24" | "25" | "26" | "27" | "28" | "end_of_month"
    - **IMPORTANT**: When user says "every Xth of the month" or "on the Xth of each month", this means the Xth DAY of EACH MONTH, NOT every X months. Always use months_indexed with day="X" and span="month", span_value=1.
    - **IMPORTANT**: If user specifies a time (e.g., "at 20:00", "at 8 PM"), include the time in the step description (e.g., "Go to dinner at 20:00") and also set a reminder with that time.
  - **reminders**: Array with:
    - **time**: "00:00" format or null (USE THIS to set reminder time if user specified a time for the step)
    - **message**: String or null

#### High-Level Schedule Structure
**Required fields:**
- **milestones**: Array of milestone objects (see Milestones System above)

## Generation Guidelines

### 1. Analyze User Intent
- Extract the core habit from conversation
- **CRITICAL**: Understand date/time expressions correctly:
  - "every Xth of the month" or "on the Xth of each month" = the Xth DAY of EACH MONTH (NOT every X months)
  - "every X months" = repeat every X months (different from "every Xth of month")
  - If user specifies a time (e.g., "at 20:00", "at 8 PM"), include it in step description AND set reminder time
- Determine appropriate frequency (daily, weekly, monthly)
- Determine difficulty level (beginner, intermediate, advanced) based on conversation complexity
- Consider user's lifestyle and constraints

### 2. Create Realistic Milestones
- Start with achievable short-term goals (e.g., 7 days streak)
- Build to medium-term consistency (e.g., 30 days streak)
- End with long-term mastery (e.g., 90 days streak or 3 months)
- Use appropriate completion_criteria type

### 3. Design Appropriate Schedule

**CRITICAL: Choosing the Right Index Type**

- **Multi-day repeating cycles** (e.g., workout every 2 days, gym rotation every 4 days: chest→back→leg→rest):
  - Use **days_indexed** with N entries (index 1, 2, 3, ... N) where N = cycle length
  - Set span="day", span_value=N (where N is the cycle length)
  - Example: 4-day gym rotation = span="day", span_value=4, days_indexed with 4 entries (index 1: chest, index 2: back, index 3: leg, index 4: rest)
  - Do NOT use weeks_indexed for this pattern

- **Weekly patterns** (e.g., gym on Monday/Wednesday/Friday every week):
  - Use **weeks_indexed** with entries for specific days of the week
  - Set span="week", span_value=1 (or 2 if user says "every 2 weeks" or "every 2nd week")
  - Each entry's content should specify day names (Monday, Tuesday, etc.)

- **Daily habits** (same activity every day):
  - span="day", span_value=how many days will be planned, create days_indexed with one or more entries
  - Example: Daily water intake = span="day", span_value=1, days_indexed with index 1

- **Weekly habits** (different activities each week):
  - span="week", create weeks_indexed with multiple weeks

- **Monthly habits** (activities on specific days of each month):
  - span="month", span_value=1 (or 3 if user says "every 3 months" or "every 3rd month"), create months_indexed entries
  - Use ONE months_indexed entry (index 1, NOT 0) with multiple content steps for different days of the month
  - **CRITICAL**: months_indexed starts with index 1, while days_indexed and weeks_indexed also start with index 1 (for consistency)
  - Example: "On the 3rd make reservation, on the 15th go at 20:00" = span:"month", span_value:1, one months_indexed entry (index 1) with two content steps: {step: "Make reservation", day: "3"} and {step: "Go to dinner at 20:00", day: "15"}, days_indexed=[], weeks_indexed=[]
  - Example: "Every 3 months, on the 3rd make reservation, on the 15th go at 20:00" = span:"month", span_value:3, one months_indexed entry (index 1) with two content steps: {step: "Make reservation", day: "3"} and {step: "Go to dinner at 20:00", day: "15"}, days_indexed=[], weeks_indexed=[]
  - Include times in step descriptions if specified (e.g., "Go to dinner at 20:00")
  - Set reminder times to match user-specified times
  - **CRITICAL**: For monthly habits with specific days, ONLY populate months_indexed. Leave days_indexed and weeks_indexed as empty arrays [].

- **All habits need**: days_indexed, weeks_indexed, AND months_indexed arrays. For monthly habits with specific days, only months_indexed should have content; days_indexed and weeks_indexed should be empty arrays [].

### 4. Include Motivation Elements
- Positive step descriptions
- Encouraging milestone reward messages
- Helpful reminder messages
- Clear benefits in description

### 5. Make It Actionable
- Steps should be specific and clear
- Include clock times in "00:00" format for daily habits when appropriate (use null if anytime in day)
- Use appropriate day names for weekly habits
- Use meaningful titles for each indexed period
- **For monthly habits with specific days**: Keep days_indexed and weeks_indexed as empty arrays []. Only populate months_indexed with the required content steps.

## Output Format
Always return a valid JSON object following this EXACT structure:

\`\`\`json
{
  "name": "string",
  "goal": "string",
  "category": "string",
  "description": "string",
  "difficulty": "beginner" | "intermediate" | "advanced",
  "high_level_schedule": {
  "milestones": [
    {
        "index": 0,
        "description": "string",
        "completion_criteria": "streak_of_days" | "streak_of_weeks" | "streak_of_months" | "percentage",
        "completion_criteria_point": number,
        "reward_message": "string"
    }
    ]
  },
  "low_level_schedule": {
    "span": "day" | "week" | "month" | "year",
    "span_value": number,
    "habit_schedule": number | null,
    "habit_repeat_count": number | null,
    "program": [
      {
        "days_indexed": [
          {
            "index": 1,
            "title": "string",
            "content": [
              {
                "step": "string",
                "clock": "00:00" | null
              }
            ],
            "reminders": [
              {
                "time": "00:00" | null,
                "message": "string" | null
              }
            ]
          }
        ],
        "weeks_indexed": [
          {
            "index": 1,
            "title": "string",
            "description": "string",
            "content": [
              {
                "step": "string",
                "day": "Monday" | "Tuesday" | "Wednesday" | "Thursday" | "Friday" | "Saturday" | "Sunday"
          }
            ],
            "reminders": [
              {
                "time": "00:00" | null,
                "message": "string" | null
              }
            ]
          }
        ],
        "months_indexed": [
          {
            "index": 1,
            "title": "string",
            "description": "string",
            "content": [
          {
                "step": "string",
                "day": "start_of_month" | "1" | "2" | "3" | "4" | "5" | "6" | "7" | "8" | "9" | "10" | "11" | "12" | "13" | "14" | "15" | "16" | "17" | "18" | "19" | "20" | "21" | "22" | "23" | "24" | "25" | "26" | "27" | "28" | "end_of_month"
          }
            ],
            "reminders": [
              {
                "time": "00:00" | null,
                "message": "string" | null
              }
            ]
          }
        ]
  }
}
\`\`\`

## Quality Checklist
- [ ] Clear, specific habit name and goal
- [ ] Difficulty level set (beginner/intermediate/advanced)
- [ ] At least 3 milestones in high_level_schedule.milestones
- [ ] Low-level schedule has span, span_value, habit_schedule, habit_repeat_count
- [ ] Program array with days_indexed, weeks_indexed, and months_indexed
- [ ] Each indexed entry has index, title, content, and reminders
- [ ] The indexed elements of days_indexed have title, content list of steps with clock (if step clock data is null it means anytime in day it can be done)
- [ ] **For monthly habits with specific days**: days_indexed and weeks_indexed are empty arrays [], only months_indexed has content
- [ ] Realistic timing and frequency
- [ ] Proper JSON formatting
- [ ] All required fields present

Now analyze this conversation and generate a habit JSON following the exact structure above:

${conversation}`;

        console.log('[generateHabitJsonInternal] Sending request to Gemini AI');
        
        // Generate the habit JSON using Gemini AI
        const result = await model.generateContent(systemPrompt);
        const response = await result.response;
        const habitJsonText = response.text();
        
        console.log('[generateHabitJsonInternal] Received response from Gemini AI, length:', habitJsonText.length);
        
        // Try to parse the JSON to validate it
        let habitJson;
        try {
            // Extract JSON from the response (in case there's extra text)
            const jsonMatch = habitJsonText.match(/\{[\s\S]*\}/);
            if (jsonMatch) {
                habitJson = JSON.parse(jsonMatch[0]);
            } else {
                throw new Error('No JSON found in response');
            }
        } catch (parseError) {
            console.error('[generateHabitJsonInternal] Failed to parse JSON from AI response:', parseError);
            console.error('[generateHabitJsonInternal] Raw response:', habitJsonText);
            return { success: false };
        }
        
        // Validate required fields
        const requiredFields = ['name', 'goal'];
        const missingFields = requiredFields.filter(field => !habitJson[field]);
        
        if (missingFields.length > 0) {
            console.error('[generateHabitJsonInternal] Missing required fields:', missingFields);
            return { success: false };
        }
        
        // Validate that at least one schedule exists
        if (!habitJson.low_level_schedule && !habitJson.high_level_schedule) {
            console.error('[generateHabitJsonInternal] No schedule found in generated habit JSON');
            return { success: false };
        }
        
        // Validate milestones are in high_level_schedule (not root level)
        if (habitJson.high_level_schedule && !habitJson.high_level_schedule.milestones) {
            console.error('[generateHabitJsonInternal] high_level_schedule exists but has no milestones');
            return { success: false };
        }
        
        if (habitJson.high_level_schedule?.milestones && habitJson.high_level_schedule.milestones.length === 0) {
            console.error('[generateHabitJsonInternal] high_level_schedule.milestones is empty');
            return { success: false };
        }
        
        // Add Firebase timestamps
        const now = new Date().toISOString();
        habitJson.created_at = now;
        // start_date will be set when user adds to calendar
        
        console.log('[generateHabitJsonInternal] Successfully generated habit JSON:', {
            name: habitJson.name,
            goal: habitJson.goal,
            hasLowLevelSchedule: !!habitJson.low_level_schedule,
            hasHighLevelSchedule: !!habitJson.high_level_schedule,
            milestonesCount: habitJson.high_level_schedule?.milestones?.length || 0
        });
        
        return {
            success: true,
            habitJson: habitJson
        };
        
    } catch (error) {
        console.error('[generateHabitJsonInternal] Error:', error);
        return { success: false };
    }
}

async function generateTaskJsonInternal(conversation: string): Promise<{success: boolean, taskJson?: any}> {
    try {
        console.log('[generateTaskJsonInternal] Starting task JSON generation');
        
        // Initialize Gemini AI
        const genAI = new GoogleGenerativeAI(geminiSecretKey.value());
        const model = genAI.getGenerativeModel({ model: 'gemini-2.0-flash' });
        
        // System prompt for task generation based on task.json schema
        const systemPrompt = `You are a specialized AI agent for creating task management structures. Your role is to analyze user conversations and generate task JSON structures that can be implemented in a task tracking application.

## Core Requirements

### 1. Basic Task Information
- **name**: Clear, concise task name (2-4 words)
- **goal**: Specific, measurable goal statement
- **category**: Categorization (Education, Career, Health, Travel, Work, Personal, Home, Finance, etc.)
- **description**: Detailed explanation of what the task involves

### 2. Task Schedule Structure
Every task must have a **task_schedule** object containing a **steps** array.

### 3. Steps Structure
Each step in the task_schedule.steps array must have:
- **index**: Sequential number starting from 1 (CRITICAL: starts with 1, NOT 0)
- **title**: Clear, concise step title
- **description**: Detailed description of what this step involves (can be null)
- **date**: Optional exact date in ISO format (YYYY-MM-DD) or null
  - If date is provided: Step is time-related and will appear on calendar
  - If date is null: Step is just a checklist item, not time-related
- **time**: Optional time of day (HH:MM format) or null - only used if date is provided
- **reminders**: Array of reminder objects (only applicable for steps with dates)

### 4. Reminders Structure
Each reminder must have:
- **offset**: Object with:
  - **unit**: "days" | "weeks" | "months"
  - **value**: Number of units before the step date (positive = before)
- **time**: Optional time of day for the reminder (HH:MM format) or null
- **message**: Optional reminder message or null

**IMPORTANT REMINDER RULES:**
- Reminders are ONLY valid for steps that have a date
- If a step has date: null, its reminders array should be empty []
- offset.value should be positive (represents days/weeks/months BEFORE the step date)

## JSON Structure
Generate a JSON object with this EXACT structure:

\`\`\`json
{
  "name": "string",
  "goal": "string",
  "category": "string",
  "description": "string",
  "task_schedule": {
  "steps": [
    {
        "index": 1,
        "title": "string",
        "description": "string | null",
        "date": "YYYY-MM-DD | null",
        "time": "HH:MM | null",
        "reminders": [
    {
            "offset": {
              "unit": "days | weeks | months",
              "value": number
            },
            "time": "HH:MM | null",
            "message": "string | null"
          }
        ]
    }
  ]
}
}
\`\`\`

## Guidelines

### Date Handling
- **Exact dates**: When user mentions specific dates (e.g., "on October 15th", "on the 20th"), use YYYY-MM-DD format
- **No dates**: When task is just step-by-step without time constraints, use null for date
- **Mixed tasks**: Some steps can have dates, others can be null (checklist items)

### Step Indexing
- Steps MUST start with index 1 (first step = index 1, second step = index 2, etc.)
- Indexes must be sequential and unique

### Reminders
- Only add reminders to steps that have dates
- Use appropriate offset values (e.g., 1 day before, 1 week before, etc.)
- Include helpful reminder messages when appropriate

\`\`\`

## Quality Checklist
- [ ] Clear, specific task name and goal
- [ ] Appropriate category assigned
- [ ] task_schedule.steps array exists
- [ ] Each step has index (starting from 1), title, description, date, time, reminders
- [ ] Steps with dates have appropriate reminders
- [ ] Steps without dates have empty reminders array
- [ ] Date format is YYYY-MM-DD (not ISO 8601 with time)
- [ ] Time format is HH:MM (24-hour format)
- [ ] Reminder offsets are positive numbers
- [ ] Proper JSON formatting
- [ ] All required fields present

Now analyze this conversation and generate a task JSON following the exact structure above:

${conversation}`;

        console.log('[generateTaskJsonInternal] Sending request to Gemini AI');
        
        // Generate the task JSON using Gemini AI
        const result = await model.generateContent(systemPrompt);
        const response = await result.response;
        const taskJsonText = response.text();
        
        console.log('[generateTaskJsonInternal] Received response from Gemini AI, length:', taskJsonText.length);
        
        // Try to parse the JSON to validate it
        let taskJson;
        try {
            // Extract JSON from the response (in case there's extra text)
            const jsonMatch = taskJsonText.match(/\{[\s\S]*\}/);
            if (jsonMatch) {
                taskJson = JSON.parse(jsonMatch[0]);
            } else {
                throw new Error('No JSON found in response');
            }
        } catch (parseError) {
            console.error('[generateTaskJsonInternal] Failed to parse JSON from AI response:', parseError);
            console.error('[generateTaskJsonInternal] Raw response:', taskJsonText);
            return { success: false };
        }
        
        // Validate required fields
        const requiredFields = ['name', 'goal', 'category', 'description', 'task_schedule'];
        const missingFields = requiredFields.filter(field => !taskJson[field]);
        
        if (missingFields.length > 0) {
            console.error('[generateTaskJsonInternal] Missing required fields:', missingFields);
            return { success: false };
        }
        
        // Validate task_schedule structure
        if (!taskJson.task_schedule || !Array.isArray(taskJson.task_schedule.steps)) {
            console.error('[generateTaskJsonInternal] Invalid task_schedule structure');
            return { success: false };
        }
        
        // Validate steps structure
        const steps = taskJson.task_schedule.steps;
        for (let i = 0; i < steps.length; i++) {
            const step = steps[i];
            const requiredStepFields = ['index', 'title', 'description', 'date', 'time', 'reminders'];
            const missingStepFields = requiredStepFields.filter(field => !(field in step));
            
            if (missingStepFields.length > 0) {
                console.error(`[generateTaskJsonInternal] Step ${i + 1} missing fields:`, missingStepFields);
                return { success: false };
            }
            
            // Validate step index (must start from 1)
            if (step.index !== i + 1) {
                console.warn(`[generateTaskJsonInternal] Step index mismatch. Expected ${i + 1}, got ${step.index}. Fixing...`);
                step.index = i + 1;
            }
            
            // Validate reminders - only allowed if step has a date
            if (!step.date && step.reminders && step.reminders.length > 0) {
                console.warn(`[generateTaskJsonInternal] Step ${i + 1} has reminders but no date. Clearing reminders.`);
                step.reminders = [];
            }
            
            // Validate reminder structure for steps with dates
            if (step.date && step.reminders) {
                for (const reminder of step.reminders) {
                    if (!reminder.offset || !reminder.offset.unit || typeof reminder.offset.value !== 'number') {
                        console.error(`[generateTaskJsonInternal] Invalid reminder structure in step ${i + 1}`);
                        return { success: false };
                    }
                }
            }
        }
        
        // Add Firebase timestamps
        const now = new Date().toISOString();
        taskJson.created_at = now;
        
        console.log('[generateTaskJsonInternal] Successfully generated task JSON:', {
            name: taskJson.name,
            goal: taskJson.goal,
            category: taskJson.category,
            stepsCount: taskJson.task_schedule.steps.length
        });
        
        return {
            success: true,
            taskJson: taskJson
        };
        
    } catch (error) {
        console.error('[generateTaskJsonInternal] Error:', error);
        return { success: false };
    }
}

interface UserAuthStatus {
    uid: string;
}

/**
 * Checks user authentication status for onCall functions.
 * Verifies authentication and rejects anonymous users.
 *
 * @param {AuthData | undefined} auth The auth object from the request.
 * @throws {HttpsError('unauthenticated')} If the user is not authenticated.
 * @throws {HttpsError('permission-denied')} If the user is anonymous.
 * @returns {Promise<UserAuthStatus>} An object containing the user's UID.
 */
async function checkUserAuthentication(auth: AuthData | undefined): Promise<UserAuthStatus> {
    const logPrefix = '[AuthCheck]';

    if (!auth) {
        console.error(`${logPrefix} User authentication data missing.`);
        throw new HttpsError('unauthenticated', 'User must be authenticated.');
    }

    const uid = auth.uid;
    const standardProvider = auth.token.firebase?.sign_in_provider;

    // Reject anonymous users
    if (standardProvider === 'anonymous') {
        console.error(`${logPrefix} Anonymous user (${uid}) attempted to access protected function. Denying.`);
        throw new HttpsError('permission-denied', 'Anonymous authentication is not allowed. Please sign in with Google or Apple.');
    }

    // Only allow Google or Apple providers
    if (standardProvider !== 'google.com' && standardProvider !== 'apple.com') {
        console.error(`${logPrefix} Invalid provider (${standardProvider}) for user ${uid}. Denying.`);
        throw new HttpsError('permission-denied', 'Only Google or Apple authentication is allowed.');
    }

    const provider = standardProvider || 'unknown';

    console.log(`${logPrefix} User verified:`, {
        userId: uid,
        provider: provider,
    });

    return {
        uid,
    };
}

async function checkUserSubscription(uid: string): Promise<boolean> {
    const logPrefix = '[SubscriptionCheck]';
    try {
        console.log(`${logPrefix} Checking subscription status for user:`, uid);
        
        const revenueCatCustomerRef = db.collection('customers').doc(uid);
        let customerDoc;
        
        try {
            customerDoc = await revenueCatCustomerRef.get();
            if (!customerDoc.exists) {
                console.log(`${logPrefix} No RevenueCat customer document found for user ${uid}. Assuming free.`);
                return false; // No customer document means not premium
            }
        } catch (error) {
            console.error(`${logPrefix} Error fetching RevenueCat data for user ${uid}:`, error);
            // If we can't fetch the official subscription data, assume free for safety
            return false; 
        }

        const customerData = customerDoc.data();
        console.log(`${logPrefix} RevenueCat customer data found for user ${uid}.`); // Simplified log

        // --- Check Subscriptions Map Directly --- 
        if (!customerData?.subscriptions) {
            console.log(`${logPrefix} No 'subscriptions' map found in customer data. Assuming free.`);
            return false;
        }

        const subscriptions = customerData.subscriptions;
        const now = new Date();

        // Define your product IDs (ensure these are correct!)
        const monthlyProductId = 'com.hunnyhun.stoicism.monthly';
        const yearlyProductId = 'com.hunnyhun.stoicism.yearly';
        const weeklyProductId = 'com.hunnyhun.stoicism.weekly'; // New weekly subscription with 3-day trial

        // Check monthly subscription
        const monthlySub = subscriptions[monthlyProductId];
        if (monthlySub) {
            console.log(`${logPrefix} Found monthly subscription entry.`);
            if (monthlySub.expires_date) {
                try {
                    const expiryDate = new Date(monthlySub.expires_date);
                    if (expiryDate > now) {
                        console.log(`${logPrefix} Monthly subscription is active (expires: ${monthlySub.expires_date}). User is Premium.`);
                        return true;
                    }
                     console.log(`${logPrefix} Monthly subscription expired (${monthlySub.expires_date}).`);
                } catch (dateError) {
                    console.error(`${logPrefix} Error parsing monthly expiry date '${monthlySub.expires_date}':`, dateError);
                }
            } else {
                console.log(`${logPrefix} Monthly subscription entry has no expiry date.`);
            }
        } else {
             console.log(`${logPrefix} No monthly subscription entry found.`);
        }
        
        // Check yearly subscription
        const yearlySub = subscriptions[yearlyProductId];
        if (yearlySub) {
            console.log(`${logPrefix} Found yearly subscription entry.`);
            if (yearlySub.expires_date) {
                try {
                    const expiryDate = new Date(yearlySub.expires_date);
                    if (expiryDate > now) {
                        console.log(`${logPrefix} Yearly subscription is active (expires: ${yearlySub.expires_date}). User is Premium.`);
                        return true;
                    }
                    console.log(`${logPrefix} Yearly subscription expired (${yearlySub.expires_date}).`);
                } catch (dateError) {
                    console.error(`${logPrefix} Error parsing yearly expiry date '${yearlySub.expires_date}':`, dateError);
                }
            } else {
                console.log(`${logPrefix} Yearly subscription entry has no expiry date.`);
            }
        } else {
            console.log(`${logPrefix} No yearly subscription entry found.`);
        }
        
        // Check weekly subscription
        const weeklySub = subscriptions[weeklyProductId];
        if (weeklySub) {
            console.log(`${logPrefix} Found weekly subscription entry.`);
            if (weeklySub.expires_date) {
                try {
                    const expiryDate = new Date(weeklySub.expires_date);
                    if (expiryDate > now) {
                        console.log(`${logPrefix} Weekly subscription is active (expires: ${weeklySub.expires_date}). User is Premium.`);
                        return true;
                    }
                    console.log(`${logPrefix} Weekly subscription expired (${weeklySub.expires_date}).`);
                } catch (dateError) {
                    console.error(`${logPrefix} Error parsing weekly expiry date '${weeklySub.expires_date}':`, dateError);
                }
            } else {
                console.log(`${logPrefix} Weekly subscription entry has no expiry date.`);
            }
        } else {
             console.log(`${logPrefix} No weekly subscription entry found.`);
        }
        
        // If no active subscription was found
        console.log(`${logPrefix} No active monthly, yearly, or weekly subscription found based on expiry dates. User is Free.`);
        return false;

    } catch (error) {
        console.error(`${logPrefix} Unexpected error during subscription check for user ${uid}:`, error);
        // Default to free (false) if any unexpected error occurs during the process
        return false;
    }
}

export const getChatHistoryV2 = onCall({
  region: 'us-central1',
  enforceAppCheck: true, // App Check enforcement enabled
}, async (request) => {
    try {
        // --- Use New Authentication Check ---
        const { uid } = await checkUserAuthentication(request.auth);
        // --- End Authentication Check ---

        console.log('👤 [getChatHistoryV2] User requesting history:', { 
            userId: uid
        });

        try {
            console.log('🔍 Attempting to query Firestore users collection for user:', uid);
            const snapshot = await db
                .collection('users')
                .doc(uid)
                .collection('conversations')
                .orderBy('lastUpdated', 'desc')
                .limit(50)
                .get();
            
            console.log('✅ Firestore query successful with docs count:', snapshot.docs.length);
            
            const conversations = snapshot.docs.map(doc => ({
                id: doc.id,
                ...doc.data()
            }));
            
            // Debug log
            console.log('📱 Chat history fetched successfully:', {
                userId: uid,
                conversationCount: conversations.length
            });
            
            return conversations;
        } catch (error) {
            console.error('❌ Error fetching chat history from Firestore:', error);
            // Return empty array as fallback, log appropriately
            return [];
        }
    } catch (error) {
         console.error('❌ Top-level error fetching chat history:', error);
         if (error instanceof HttpsError) {
             throw error; // Re-throw HttpsErrors (like 'unauthenticated' from middleware)
         }
         // Throw a different HttpsError or a generic one for client handling
         throw new HttpsError('internal', 'Failed to fetch chat history.');
    }
});

export const getHabitsV2 = onCall({
  region: 'us-central1',
  enforceAppCheck: true,
}, async (request) => {
    try {
        // --- Use New Authentication Check ---
        const { uid } = await checkUserAuthentication(request.auth);
        // --- End Authentication Check ---

        console.log('👤 [getHabitsV2] Authenticated user requesting habits:', { userId: uid });

        try {
            console.log('🔍 Attempting to query Firestore habits collection for user:', uid);
            // Query without orderBy first to avoid index issues, then sort in memory
            const snapshot = await db
                .collection('users')
                .doc(uid)
                .collection('habits')
                .get();
            
            console.log('✅ Firestore habits query successful with docs count:', snapshot.docs.length);
            
            const habits = snapshot.docs.map(doc => {
                const data = doc.data();
                
                // Convert Firestore timestamps to ISO strings for iOS compatibility
                const processedData: any = {
                    id: doc.id,
                    ...data
                };
                
                // Handle created_at timestamp (can be Firestore Timestamp or ISO string)
                if (data.created_at) {
                    if (typeof data.created_at.toDate === 'function') {
                        processedData.created_at = data.created_at.toDate().toISOString();
                    } else if (typeof data.created_at === 'string') {
                        processedData.created_at = data.created_at;
                    }
                }
                
                // Handle start_date timestamp (can be Firestore Timestamp or ISO string)
                if (data.start_date) {
                    if (typeof data.start_date.toDate === 'function') {
                        processedData.start_date = data.start_date.toDate().toISOString();
                    } else if (typeof data.start_date === 'string') {
                        processedData.start_date = data.start_date;
                    }
                }
                
                // Handle lastReminderUpdate timestamp
                if (data.lastReminderUpdate && typeof data.lastReminderUpdate.toDate === 'function') {
                    processedData.lastReminderUpdate = data.lastReminderUpdate.toDate().toISOString();
                }
                
                // Handle any other timestamp fields that might exist
                if (data.updatedAt && typeof data.updatedAt.toDate === 'function') {
                    processedData.updatedAt = data.updatedAt.toDate().toISOString();
                }
                
                // Ensure isActive field is present (default to true if missing for backward compatibility)
                if (processedData.isActive === undefined) {
                    processedData.isActive = true;
                }
                
                return processedData;
            });
            
            // Sort by created_at in memory (most recent first)
            habits.sort((a, b) => {
                const dateA = a.created_at || '';
                const dateB = b.created_at || '';
                return dateB.localeCompare(dateA); // Descending order
            });
            
            // Debug log
            console.log('📱 Habits fetched successfully:', {
                userId: uid,
                habitCount: habits.length
            });
            
            return habits;
        } catch (error) {
            console.error('❌ Error fetching habits from Firestore:', error);
            // Return empty array as fallback, log appropriately
            return [];
        }
    } catch (error) {
         console.error('❌ Top-level error fetching habits:', error);
         if (error instanceof HttpsError) {
             throw error;
         }
         throw new HttpsError('internal', 'An unexpected error occurred while fetching habits.');
     }
});

export const getTasksV2 = onCall({
  region: 'us-central1',
  enforceAppCheck: true,
}, async (request) => {
    try {
        // --- Use New Authentication Check ---
        const { uid } = await checkUserAuthentication(request.auth);
        // --- End Authentication Check ---

        console.log('👤 [getTasksV2] Authenticated user requesting tasks:', { userId: uid });

        try {
            console.log('🔍 Attempting to query Firestore tasks collection for user:', uid);
            const snapshot = await db
                .collection('users')
                .doc(uid)
                .collection('tasks')
                .orderBy('createdAt', 'desc')
                .get();
            
            console.log('✅ Firestore tasks query successful with docs count:', snapshot.docs.length);
            
            const tasks = snapshot.docs.map(doc => {
                const data = doc.data();
                
                // Debug: Log raw data from Firestore
                console.log(`🔍 [getTasksV2] Raw task data for ${doc.id}:`, {
                    name: data.name,
                    isActive: data.isActive,
                    isActiveType: typeof data.isActive,
                    hasIsActive: 'isActive' in data
                });
                
                // Convert Firestore timestamps to ISO strings for iOS compatibility
                const processedData: any = {
                    id: doc.id,
                    ...data
                };
                
                // Handle createdAt (ISO8601 string)
                if (data.createdAt) {
                    if (typeof data.createdAt === 'string') {
                        processedData.createdAt = data.createdAt;
                    } else if (typeof data.createdAt.toDate === 'function') {
                    processedData.createdAt = data.createdAt.toDate().toISOString();
                    }
                }
                
                // Handle completedAt timestamp
                if (data.completedAt && typeof data.completedAt.toDate === 'function') {
                    processedData.completedAt = data.completedAt.toDate().toISOString();
                }
                
                // Handle startDate (ISO8601 string)
                if (data.startDate) {
                    if (typeof data.startDate === 'string') {
                        processedData.startDate = data.startDate;
                    } else if (typeof data.startDate.toDate === 'function') {
                    processedData.startDate = data.startDate.toDate().toISOString();
                }
                }
                
                // Handle task_schedule structure
                if (data.task_schedule && typeof data.task_schedule === 'object') {
                    const taskSchedule = { ...data.task_schedule };
                    if (taskSchedule.steps && Array.isArray(taskSchedule.steps)) {
                        taskSchedule.steps = taskSchedule.steps.map((step: any) => {
                        const processedStep = { ...step };
                            // Handle scheduledDate timestamp if present
                        if (step.scheduledDate && typeof step.scheduledDate.toDate === 'function') {
                            processedStep.scheduledDate = step.scheduledDate.toDate().toISOString();
                        }
                            // Date field is already a string (YYYY-MM-DD format)
                            // Process reminders if they exist
                            if (step.reminders && Array.isArray(step.reminders)) {
                                processedStep.reminders = step.reminders;
                        }
                        return processedStep;
                    });
                    }
                    processedData.task_schedule = taskSchedule;
                }
                
                // Ensure isActive field is present (default to true if missing for backward compatibility)
                // IMPORTANT: Only default to true if the field is actually missing (undefined or null)
                // If it's explicitly false, preserve it
                if (processedData.isActive === undefined || processedData.isActive === null) {
                    console.log(`⚠️ [getTasksV2] Task ${doc.id} missing isActive field, defaulting to true`);
                    processedData.isActive = true;
                } else {
                    // Preserve the boolean value as-is (don't convert, just ensure it's a boolean)
                    // If it's already a boolean, keep it; if it's a string, convert properly
                    if (typeof processedData.isActive === 'string') {
                        processedData.isActive = processedData.isActive.toLowerCase() === 'true';
                    } else {
                        processedData.isActive = !!processedData.isActive; // Convert to boolean
                    }
                    console.log(`✅ [getTasksV2] Task ${doc.id} isActive preserved as: ${processedData.isActive} (type: ${typeof processedData.isActive})`);
                }
                
                return processedData;
            });
            
            // Debug log
            console.log('📱 Tasks fetched successfully:', {
                userId: uid,
                taskCount: tasks.length
            });
            
            return tasks;
        } catch (error) {
            console.error('❌ Error fetching tasks from Firestore:', error);
            // Return empty array as fallback, log appropriately
            return [];
        }
    } catch (error) {
         console.error('❌ Top-level error fetching tasks:', error);
         if (error instanceof HttpsError) {
             throw error;
         }
         throw new HttpsError('internal', 'An unexpected error occurred while fetching tasks.');
     }
});

async function generateConversationTitle(userMessage: string, aiResponse: string, chatMode: string = 'task'): Promise<string> {
    try {
        console.log('📝 Generating conversation title from:', {
            userMessage: userMessage.substring(0, 50) + '...',
            aiResponse: aiResponse.substring(0, 50) + '...'
        });
        
        // Get the API key using the defineSecret API
        const apiKey = geminiSecretKey.value();
        
        if (!apiKey) {
            console.error('❌ Gemini API key is not found');
            return "Spiritual Conversation";
        }
        
        // Initialize Gemini with the more capable model
        const genAI = new GoogleGenerativeAI(apiKey);
        const model = genAI.getGenerativeModel({ model: 'gemini-2.0-flash' });
        
        // Create improved prompt for title generation based on chat mode
        const modeContext = chatMode === 'habit' ? 'habit-building and virtue development' : 'philosophical wisdom and guidance';
        const exampleTitles = chatMode === 'habit' ? 
            '- Building Morning Routine\n- Creating Meditation Habit\n- Developing Discipline\n- Personal Growth Plan\n- Daily Reflection Practice' :
            '- Finding Inner Peace\n- Understanding Personal Wisdom\n- Seeking Virtue\n- Personal Growth Journey\n- Overcoming Challenges';
            
        const prompt = `Detect the users language and create a meaningful conversation title (4-5 words max) focused on ${modeContext} that captures the essence of this conversation:

User's Message: "${userMessage}"
AI's Response: "${aiResponse}"

Guidelines:
- Make it meaningful and specific to ${chatMode === 'habit' ? 'habit building' : 'philosophical wisdom'}
- Focus on the core theme or lesson
- Keep it concise (4-5 words max)
- Make it unique and specific to this conversation
- Do not include quotes or special characters

Examples of good titles:
${exampleTitles}

Return only the title, nothing else.`;
        
        // Add detailed logging for the prompt
        console.log('📝 Full prompt for title generation:');
        console.log('----------------------------------------');
        console.log(prompt);
        console.log('----------------------------------------');
        console.log('📝 Prompt components:');
        console.log('- User message length:', userMessage.length);
        console.log('- AI response length:', aiResponse.length);
        console.log('- Total prompt length:', prompt.length);
        
        // Generate title using Gemini
        console.log('🤖 Generating title with Gemini 1.5 Pro...');
        const result = await model.generateContent(prompt);
        const title = result.response.text().trim();
        
        console.log('📝 Raw title from Gemini:', title);
        
        // Ensure the title isn't too long and remove quotes if present
        const cleanTitle = title.replace(/["']/g, '').trim();
        const finalTitle = cleanTitle.length > 30 ? cleanTitle.substring(0, 27) + '...' : cleanTitle;
        
        console.log('✅ Generated title:', finalTitle);
        return finalTitle;
    } catch (error) {
        console.error('❌ Error generating title:', error);
        // Create a simple title from the first few words of the user message
        const words = userMessage.split(' ').slice(0, 4);
        const fallbackTitle = words.join(' ') + (words.length > 4 ? '...' : '');
        console.log('📝 Using fallback title:', fallbackTitle);
        return fallbackTitle;
    }
}

export const processChatMessageV2 = onRequest({
    region: 'us-central1',
    secrets: [geminiSecretKey]
}, async (req, res) => {
    try {
        // Set CORS headers first
        res.setHeader('Access-Control-Allow-Origin', '*');
        res.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS');
        res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization');
        res.setHeader('Access-Control-Max-Age', '86400');
        
        // Handle CORS preflight
        if (req.method === 'OPTIONS') {
            res.status(200).end();
            return;
        }
        
        // Validate HTTP method
        if (req.method !== 'POST') {
            res.status(405).send('Method Not Allowed');
            return;
        }

        // Parse request data
        const { message, conversationId, stream = false, chatMode = 'task' } = req.body;
        
        // Determine if this is a streaming request
        const isStreamingRequest = stream === true;

        // Set up appropriate content headers
        if (isStreamingRequest) {
            // Set up SSE headers for streaming
            res.writeHead(200, {
                'Content-Type': 'text/plain; charset=utf-8',
                'Cache-Control': 'no-cache',
                'Connection': 'keep-alive',
            });
        } else {
            // Set up JSON headers for regular response
            res.setHeader('Content-Type', 'application/json');
        }

        // Helper function to send SSE data (only for streaming)
        const sendSSE = (type: string, data: any) => {
            if (isStreamingRequest) {
                const payload = JSON.stringify({ type, data });
                res.write(`data: ${payload}\n\n`);
            }
        };

        // Helper function to send final response
        const sendResponse = (responseData: any, statusCode: number = 200) => {
            if (isStreamingRequest) {
                sendSSE('complete', responseData);
                res.end();
            } else {
                res.status(statusCode).json(responseData);
            }
        };

        // Helper function to send error
        const sendError = (message: string, statusCode: number = 500) => {
            if (isStreamingRequest) {
                sendSSE('error', { message });
                res.end();
            } else {
                res.status(statusCode).json({ error: message });
            }
        };

        // --- Add IP Rate Limiting Check --- 
        const clientIp = req.ip || req.connection.remoteAddress;
        if (clientIp) {
            try {
                await checkAndIncrementIpRateLimit(clientIp);
            } catch (rateLimitError) {
                console.warn('[processChatMessageV2] Rate limit exceeded for IP:', clientIp);
                sendError('Rate limit exceeded. Please try again later.', 429);
                return;
            }
        } else {
            console.warn('[processChatMessageV2] Client IP address not found in request. Cannot apply rate limit.');
        }
        // --- End IP Rate Limiting Check ---

        // --- Authentication Check (now for onRequest) ---
        const authHeader = req.headers.authorization;
        const idToken = authHeader?.replace('Bearer ', '');
        if (!idToken) {
            console.error('[processChatMessageV2] Missing authentication token');
            sendError('Missing authentication token', 401);
            return;
        }

        let uid: string;
        let provider: string;
        try {
            const decodedToken = await auth.verifyIdToken(idToken);
            uid = decodedToken.uid;
            provider = decodedToken.firebase?.sign_in_provider || 'unknown';
            
            // Reject anonymous users
            if (provider === 'anonymous') {
                console.error('[processChatMessageV2] Anonymous user attempted to access. Denying.');
                sendError('Anonymous authentication is not allowed. Please sign in with Google or Apple.', 403);
                return;
            }
            
            // Only allow Google or Apple providers
            if (provider !== 'google.com' && provider !== 'apple.com') {
                console.error('[processChatMessageV2] Invalid provider. Denying.');
                sendError('Only Google or Apple authentication is allowed.', 403);
                return;
            }
            
            console.log('[processChatMessageV2] User authenticated:', {
                userId: uid,
                provider: provider,
                chatMode
            });
        } catch (authError) {
            console.error('[processChatMessageV2] Authentication error:', authError);
            sendError('Invalid authentication token', 401);
            return;
        }
        
        // Validate chat mode
        if (!['task', 'habit'].includes(chatMode)) {
            console.error('[processChatMessageV2] Invalid chat mode:', chatMode);
            sendError('Invalid chat mode. Must be "task" or "habit".', 400);
            return;
        }
        // --- End Authentication Check ---

        // Validate message
        if (!message || typeof message !== 'string' || message.trim().length === 0) {
            sendError('Message is required and cannot be empty.', 400);
            return;
        }

        // --- Add Backend Character Limit --- 
        let trimmedMessage = message.trim();
        const MAX_BACKEND_CHARS = 1000;
        if (trimmedMessage.length > MAX_BACKEND_CHARS) {
            console.warn(`[processChatMessageV2] Message length (${trimmedMessage.length}) exceeds backend limit (${MAX_BACKEND_CHARS}). Truncating.`);
            trimmedMessage = trimmedMessage.substring(0, MAX_BACKEND_CHARS);
        }
        // --- End Backend Character Limit ---

        const userRef = db.collection('users').doc(uid);

        // --- Subscription Required Check ---
        const isPremium = await checkUserSubscription(uid);
        console.log('💲 User subscription status:', isPremium ? 'Premium' : 'No Subscription');

        if (!isPremium) {
            console.log('🚫 User does not have active subscription. Access denied.');
            sendError('A premium subscription is required to use AI features. Please subscribe to continue.', 403);
            return;
        }

        console.log('✅ Premium user verified. Proceeding with AI request.');

        // Debug log
        console.log('💬 Proceeding with message processing:', {
            userId: uid,
            messageLength: trimmedMessage.length,
            conversationId: conversationId || 'new',
            subscription: isPremium ? 'Premium' : 'Free',
            streaming: isStreamingRequest
        });

        // Get or create conversation
        console.log('🔍 Creating conversation reference for user:', uid);
        const conversationRef = conversationId
            ? db.collection('users').doc(uid).collection('conversations').doc(conversationId)
            : db.collection('users').doc(uid).collection('conversations').doc();

        console.log('🔍 Conversation reference path:', conversationRef.path);

        // Get conversation history
        let conversationData: ConversationData = { messages: [], chatMode };
        let existingTitle: string | undefined = undefined;
        
        try {
            const conversationDoc = await conversationRef.get();
            if (conversationDoc.exists) {
                const data = conversationDoc.data();
                if (data) {
                    conversationData = data as ConversationData;
                    existingTitle = data.title;
                    console.log('✅ Conversation document retrieved successfully. Message count:', conversationData.messages.length);
                } else {
                    console.log('⚠️ Conversation document exists but has no data.');
                }
            } else {
                console.log('ℹ️ No existing conversation document found. Will create new one.');
            }
        } catch (error) {
            console.error('❌ Error retrieving conversation document:', error);
        }

        // Add user message to local array first
        const userMessageEntry = {
            role: 'user',
            content: trimmedMessage,
            timestamp: new Date().toISOString()
        };

        // Create a combined history for Gemini
        const historyForGemini = [
            ...conversationData.messages.map(msg => ({ role: msg.role, parts: [{ text: msg.content }] })),
            { role: 'user', parts: [{ text: trimmedMessage }] }
        ];

        // Get API key from Secret Manager
        console.log('🤖 Initializing Gemini AI with Secret Manager key...');
        let responseText = '';
        let title = existingTitle;

        try {
            const apiKey = geminiSecretKey.value();
            if (!apiKey) {
                console.error('❌ Gemini API key is not found');
                sendError('API key configuration error.', 500);
                return;
            }
            console.log('✅ Successfully retrieved API key.');

            const genAI = new GoogleGenerativeAI(apiKey);
            const model = genAI.getGenerativeModel({ model: 'gemini-2.0-flash' });

            // Start chat session with history
            const chat = model.startChat({
                history: historyForGemini.slice(0, -1),
                generationConfig: {
                    maxOutputTokens: 1500, // Increased for comprehensive habit suggestions
                    temperature: 0.7,
                    topK: 40,
                    topP: 0.95
                }
            });

            // Get the appropriate system prompt based on chat mode
            const systemPrompt = getSystemPrompt(chatMode);
            console.log(`[processChatMessageV2] Using ${chatMode} mode system prompt`);

            // Fetch user profile and build personalization context
            const userProfile = await getUserProfile(uid);
            const userContextPrompt = buildUserContextPrompt(userProfile);
            
            // Send the system instruction and user personalization context
            await chat.sendMessage(systemPrompt);
            if (userContextPrompt) {
                await chat.sendMessage(userContextPrompt);
            }

            // Generate response (streaming or non-streaming)
            console.log('🤖 Sending message to Gemini...');
            
            if (isStreamingRequest) {
                // Send start event for streaming
                sendSSE('start', { conversationId: conversationRef.id });
                
                // Generate streaming response
                const result = await chat.sendMessageStream(trimmedMessage);
                
                // Stream the response
                for await (const chunk of result.stream) {
                    const chunkText = chunk.text();
                    responseText += chunkText;
                    
                    // Send each chunk to the client
                    sendSSE('chunk', { text: chunkText });
                }
                
                // Send end event
                sendSSE('end', { fullText: responseText });
            } else {
                // Generate regular response
                const result = await chat.sendMessage(trimmedMessage);
                responseText = result.response.text();
            }

            console.log('✅ Gemini response generated successfully.');

            // Check if we should generate a habit JSON (only in habit mode)
            let habitJson = null;
            if (chatMode === 'habit' && shouldGenerateHabit(responseText)) {
                console.log('🎯 Detected HABITGEN flag, generating habit JSON...');
                try {
                    // Remove the HABITGEN flag from the response text before showing to user
                    responseText = responseText.replace(/\[HABITGEN\s*=\s*True\]/gi, '').trim();
                    
                    // Build conversation context for habit generation
                    const conversationContext = buildConversationContext(conversationData.messages, trimmedMessage, responseText);
                    
                    // Call the generateHabitJson function internally
                    const habitResult = await generateHabitJsonInternal(conversationContext);
                    if (habitResult.success) {
                        habitJson = habitResult.habitJson;
                        console.log('✅ Habit JSON generated successfully:', habitJson.name);
                        
                        // Append the habit JSON to the response
                        responseText += `\n\n**Your Personalized Habit Program:**\n\`\`\`json\n${JSON.stringify(habitJson, null, 2)}\n\`\`\``;
                    } else {
                        console.warn('⚠️ Failed to generate habit JSON, continuing with regular response');
                    }
                } catch (error) {
                    console.error('❌ Error generating habit JSON:', error);
                    // Continue with regular response if habit generation fails
                }
            }
            
            // Check if we should generate a task JSON (only in task mode)
            let taskJson = null;
            if (chatMode === 'task' && shouldGenerateTask(responseText)) {
                console.log('🎯 Detected TASKGEN flag, generating task JSON...');
                try {
                    // Remove the TASKGEN flag from the response text before showing to user
                    responseText = responseText.replace(/\[TASKGEN\s*=\s*True\]/gi, '').trim();
                    
                    // Build conversation context for task generation
                    const conversationContext = buildConversationContext(conversationData.messages, trimmedMessage, responseText);
                    
                    // Call the generateTaskJson function internally
                    const taskResult = await generateTaskJsonInternal(conversationContext);
                    if (taskResult.success) {
                        taskJson = taskResult.taskJson;
                        console.log('✅ Task JSON generated successfully:', taskJson.name);
                        
                        // Append the task JSON to the response
                        responseText += `\n\n**Your Task Breakdown:**\n\`\`\`json\n${JSON.stringify(taskJson, null, 2)}\n\`\`\``;
                    } else {
                        console.warn('⚠️ Failed to generate task JSON, continuing with regular response');
                    }
                } catch (error) {
                    console.error('❌ Error generating task JSON:', error);
                    // Continue with regular response if task generation fails
                }
            }

            // Generate title only if it's a new conversation
            if (!title) {
                console.log('📝 Generating new title for conversation');
                title = await generateConversationTitle(trimmedMessage, responseText, chatMode);
            } else {
                console.log('📝 Using existing title:', title);
            }

        } catch (error) {
            console.error('❌ Error with Gemini API or Title Generation:', error);
            responseText = "I apologize, but I encountered an issue connecting to my knowledge base. Please try again shortly.";
            title = existingTitle ?? "Conversation Error";
        }

        // Prepare assistant message entry
        const assistantMessageEntry = {
            role: 'assistant',
            content: responseText,
            timestamp: new Date().toISOString()
        };

        // --- Firestore Updates ---
        const batch = db.batch();

        // 1. Update Conversation Document
        const conversationUpdateData = {
            messages: [...conversationData.messages, userMessageEntry, assistantMessageEntry],
            lastUpdated: FieldValue.serverTimestamp(),
            title: title,
            chatMode: chatMode
        };
        batch.set(conversationRef, conversationUpdateData, { merge: true });
        console.log('🔢 Added conversation update to batch.');

        // 2. Update User Document (only lastActive timestamp)
        const userUpdateData: { [key: string]: any } = {
            lastActive: FieldValue.serverTimestamp()
        };
        batch.set(userRef, userUpdateData, { merge: true });
        console.log(`🔢 Added user lastActive update to batch.`);

        // Commit the batch
        try {
            console.log('💾 Committing batch update to Firestore...');
            await batch.commit();
            console.log('✅ Batch commit successful.');
        } catch (error) {
            console.error('❌ Error committing batch update:', error);
            sendError('Failed to save message and update counts.', 500);
            return;
        }

        // Debug log
        console.log('💬 Message processed successfully');

        // Send final response
        const finalResponse = {
            role: 'assistant',
            message: responseText,
            response: responseText,
            conversationId: conversationRef.id,
            title: title
        };

        sendResponse(finalResponse);

    } catch (error) {
        console.error('❌ Top-level error processing message:', error);
        const errorMessage = error instanceof Error ? error.message : 'An unexpected error occurred while processing your message.';
        
        if ((res as any).headersSent) {
            // If headers already sent (streaming case), write error as SSE
            res.write(`data: ${JSON.stringify({ type: 'error', data: { message: errorMessage } })}\n\n`);
            res.end();
        } else {
            res.status(500).json({ error: errorMessage });
        }
    }
});

async function checkAndIncrementIpRateLimit(ip: string): Promise<void> {
    const logPrefix = '[RateLimit]';
    if (!ip) {
        console.warn(`${logPrefix} IP address is missing. Skipping rate limit check.`);
        // Decide if you want to allow or deny requests without an IP.
        // Allowing might be okay for internal/trusted calls, but risky otherwise.
        return; // Allow for now, but consider throwing an error.
    }

    const rateLimitRef = db.collection('ipRateLimits').doc(ip);
    const windowMillis = IP_RATE_LIMIT_WINDOW_SECONDS * 1000;

    try {
        await db.runTransaction(async (transaction) => {
            const doc = await transaction.get(rateLimitRef);
            const currentTimeMillis = Date.now(); // Get current time for comparison

            if (!doc.exists) {
                console.log(`${logPrefix} First request from IP: ${ip}. Creating record.`);
                // First request from this IP in a while
                transaction.set(rateLimitRef, {
                    count: 1,
                    // Store window start as milliseconds since epoch for easier comparison
                    windowStartMillis: currentTimeMillis 
                });
                return; // Allowed
            }

            const data = doc.data();
            const windowStartMillis = data?.windowStartMillis;
            let currentCount = data?.count || 0;

            if (!windowStartMillis || typeof windowStartMillis !== 'number') {
                 console.warn(`${logPrefix} Invalid windowStartMillis for IP: ${ip}. Resetting.`);
                 // Invalid data, reset
                 transaction.set(rateLimitRef, { count: 1, windowStartMillis: currentTimeMillis });
                 return; // Allow this request
            }

            // Check if the window has expired
            if (currentTimeMillis - windowStartMillis > windowMillis) {
                console.log(`${logPrefix} Rate limit window expired for IP: ${ip}. Resetting count.`);
                // Window expired, reset count
                transaction.update(rateLimitRef, { count: 1, windowStartMillis: currentTimeMillis });
                return; // Allowed
            }

            // Window is still active, check count
            if (currentCount >= IP_RATE_LIMIT_MAX_REQUESTS) {
                console.warn(`${logPrefix} Rate limit exceeded for IP: ${ip}. Count: ${currentCount}`);
                // Limit exceeded
                throw new HttpsError(
                    'resource-exhausted',
                    `Too many requests from this IP address. Please try again in ${IP_RATE_LIMIT_WINDOW_SECONDS} seconds.`,
                    { ip: ip } // Optional details
                );
            }

            // Within limit, increment count
            console.log(`${logPrefix} Incrementing count for IP: ${ip}. New count: ${currentCount + 1}`);
            transaction.update(rateLimitRef, { count: FieldValue.increment(1) });
            // Allowed
        });
        console.log(`${logPrefix} IP ${ip} is within rate limits.`);
    } catch (error) {
        if (error instanceof HttpsError) {
            throw error; // Re-throw HttpsError (rate limit exceeded)
        }
        // Log other transaction errors but potentially allow the request?
        // Or throw a generic internal error?
        console.error(`${logPrefix} Error during rate limit transaction for IP ${ip}:`, error);
        // Decide on behavior for transaction errors. Throwing is safer.
        throw new HttpsError('internal', 'Failed to verify request rate limit.');
    }
}

// MARK: - Share Link Functions

/**
 * Creates a shareable link for a habit or task
 * Stores the data in Firestore and returns a short URL
 */
export const createShareLink = onCall({
  region: 'us-central1',
  enforceAppCheck: true,
}, async (request) => {
  try {
    const { uid } = await checkUserAuthentication(request.auth);
    const { type, itemId } = request.data; // type: 'habit' | 'task', itemId: the habit/task document ID
    
    if (!type || (type !== 'habit' && type !== 'task')) {
      throw new HttpsError('invalid-argument', 'Type must be "habit" or "task"');
    }
    
    if (!itemId || typeof itemId !== 'string') {
      throw new HttpsError('invalid-argument', 'itemId is required');
    }
    
    console.log(`🔗 [createShareLink] Creating share link for ${type}: ${itemId}`);
    
    // Get the habit or task from Firestore
    const itemRef = db.collection('users').doc(uid).collection(type === 'habit' ? 'habits' : 'tasks').doc(itemId);
    const itemDoc = await itemRef.get();
    
    if (!itemDoc.exists) {
      throw new HttpsError('not-found', `${type} not found`);
    }
    
    const itemData = itemDoc.data();
    if (!itemData) {
      throw new HttpsError('not-found', `${type} data not found`);
    }
    
    // Get the original owner (who created the habit/task)
    // Check for createdBy field, or default to current user if not found
    const originalOwner = itemData.createdBy || uid;
    
    // Generate a unique share ID
    const shareId = `${Date.now()}-${Math.random().toString(36).substring(2, 9)}`;
    
    // Store in separate collections: sharedHabits or sharedTasks
    const collectionName = type === 'habit' ? 'sharedHabits' : 'sharedTasks';
    
    const sharedItemData = {
      itemData: itemData,
      originalOwner: originalOwner, // Who originally created the habit/task
      sharedBy: uid, // Who created the share link (could be different from original owner)
      sharedAt: FieldValue.serverTimestamp(),
      expiresAt: null, // Could add expiration if needed
      viewCount: 0,
      importCount: 0,
      importedBy: [], // Array of user IDs who imported this
      lastImportedAt: null
    };
    
    await db.collection(collectionName).doc(shareId).set(sharedItemData);
    
    // Generate the share URL
    // In production, this would be your domain: https://calendo.app/share/{shareId}
    // For now, using deep link format that can be converted to universal link later
    const shareUrl = `calendo://share/${type}/${shareId}`;
    
    console.log(`✅ [createShareLink] Created share link: ${shareUrl}`);
    
    return {
      shareId: shareId,
      shareUrl: shareUrl,
      // Also return web URL format for universal links
      webUrl: `https://calendo.app/share/${type}/${shareId}` // Replace with your actual domain
    };
  } catch (error) {
    console.error('❌ [createShareLink] Error:', error);
    if (error instanceof HttpsError) {
      throw error;
    }
    throw new HttpsError('internal', 'Failed to create share link');
  }
});

/**
 * Retrieves a shared habit or task by share ID
 * Public endpoint - no authentication required
 */
export const getSharedItem = onCall({
  region: 'us-central1',
  enforceAppCheck: false, // Public endpoint
}, async (request) => {
  try {
    const { type, shareId } = request.data;
    
    if (!type || (type !== 'habit' && type !== 'task')) {
      throw new HttpsError('invalid-argument', 'Type must be "habit" or "task"');
    }
    
    if (!shareId || typeof shareId !== 'string') {
      throw new HttpsError('invalid-argument', 'shareId is required');
    }
    
    console.log(`🔗 [getSharedItem] Retrieving shared ${type}: ${shareId}`);
    
    // Get from the appropriate collection
    const collectionName = type === 'habit' ? 'sharedHabits' : 'sharedTasks';
    const sharedItemRef = db.collection(collectionName).doc(shareId);
    const sharedItemDoc = await sharedItemRef.get();
    
    if (!sharedItemDoc.exists) {
      throw new HttpsError('not-found', 'Share link not found or expired');
    }
    
    const sharedItemData = sharedItemDoc.data();
    if (!sharedItemData) {
      throw new HttpsError('not-found', 'Share link data not found');
    }
    
    // Check expiration (if implemented)
    if (sharedItemData.expiresAt) {
      const expiresAt = sharedItemData.expiresAt.toDate();
      if (expiresAt < new Date()) {
        throw new HttpsError('not-found', 'Share link has expired');
      }
    }
    
    // Increment view count
    await sharedItemRef.update({
      viewCount: FieldValue.increment(1)
    });
    
    // Return the item data (without sensitive user info)
    const itemData = sharedItemData.itemData;
    
    // Remove user-specific fields that shouldn't be shared
    delete itemData.createdBy;
    delete itemData.startDate; // User's start date shouldn't be shared
    delete itemData.createdAt; // User's creation date shouldn't be shared
    
    // Reset IDs and dates for import
    const cleanedData = {
      ...itemData,
      id: undefined, // Will be regenerated on import
      startDate: null,
      createdAt: null,
      isActive: false // Imported items start as inactive
    };
    
    console.log(`✅ [getSharedItem] Retrieved shared ${type}`);
    
    return {
      type: type,
      itemData: cleanedData
    };
  } catch (error) {
    console.error('❌ [getSharedItem] Error:', error);
    if (error instanceof HttpsError) {
      throw error;
    }
    throw new HttpsError('internal', 'Failed to retrieve shared item');
  }
});

/**
 * Records an import event when a user imports a shared habit or task
 * Tracks analytics: who imported, when, and increments import count
 */
export const recordShareImport = onCall({
  region: 'us-central1',
  enforceAppCheck: true,
}, async (request) => {
  try {
    const { uid } = await checkUserAuthentication(request.auth);
    const { type, shareId } = request.data;
    
    if (!type || (type !== 'habit' && type !== 'task')) {
      throw new HttpsError('invalid-argument', 'Type must be "habit" or "task"');
    }
    
    if (!shareId || typeof shareId !== 'string') {
      throw new HttpsError('invalid-argument', 'shareId is required');
    }
    
    console.log(`📊 [recordShareImport] Recording import for ${type}: ${shareId} by user: ${uid}`);
    
    // Get from the appropriate collection
    const collectionName = type === 'habit' ? 'sharedHabits' : 'sharedTasks';
    const sharedItemRef = db.collection(collectionName).doc(shareId);
    const sharedItemDoc = await sharedItemRef.get();
    
    if (!sharedItemDoc.exists) {
      throw new HttpsError('not-found', 'Share link not found');
    }
    
    const sharedItemData = sharedItemDoc.data();
    if (!sharedItemData) {
      throw new HttpsError('not-found', 'Share link data not found');
    }
    
    // Check if user already imported this (to avoid duplicate counts)
    const importedBy = sharedItemData.importedBy || [];
    const alreadyImported = importedBy.includes(uid);
    
    // Update import statistics
    const updateData: any = {
      lastImportedAt: FieldValue.serverTimestamp()
    };
    
    if (!alreadyImported) {
      // First time this user imports
      updateData.importCount = FieldValue.increment(1);
      updateData.importedBy = FieldValue.arrayUnion(uid);
    }
    
    await sharedItemRef.update(updateData);
    
    console.log(`✅ [recordShareImport] Recorded import for ${type}: ${shareId}${alreadyImported ? ' (duplicate)' : ''}`);
    
    return {
      success: true,
      isNewImport: !alreadyImported,
      totalImports: (sharedItemData.importCount || 0) + (alreadyImported ? 0 : 1)
    };
  } catch (error) {
    console.error('❌ [recordShareImport] Error:', error);
    if (error instanceof HttpsError) {
      throw error;
    }
    throw new HttpsError('internal', 'Failed to record share import');
  }
});

export const generateHabitJson = onCall({
    region: 'us-central1',
    enforceAppCheck: true,
    secrets: [geminiSecretKey]
}, async (request) => {
    const logPrefix = '[generateHabitJson]';
    console.log(`${logPrefix} Starting habit JSON generation`);
    
    try {
        // Get the conversation from the request
        const { conversation } = request.data;
        
        if (!conversation || typeof conversation !== 'string') {
            console.error(`${logPrefix} Invalid conversation input:`, conversation);
            throw new HttpsError('invalid-argument', 'Conversation is required and must be a string');
        }
        
        console.log(`${logPrefix} Conversation length:`, conversation.length);
        
        // Initialize Gemini AI
        const genAI = new GoogleGenerativeAI(geminiSecretKey.value());
        const model = genAI.getGenerativeModel({ model: 'gemini-2.0-flash' });
        
        // System prompt for habit generation
        const systemPrompt = `You are a specialized AI agent for creating personalized habit plans. Your role is to analyze user conversations and generate comprehensive habit JSON structures that can be implemented in a habit tracking application.

## Core Requirements

### 1. Basic Habit Information
- **name**: Clear, concise habit name (2-4 words)
- **goal**: Specific, measurable goal statement
- **category**: Optional categorization (health, productivity, mindfulness, fitness, learning, etc.)
- **description**: Detailed explanation of what the habit involves
- **difficulty**: "beginner" | "intermediate" | "advanced" - Determined based on conversation complexity and user experience

### 2. Milestones System
Every habit must have at least 3 milestones:
- **Foundation milestone**: First part completion, understand the habit needs and get used to.
- **Building milestone**: Middle part completion, more success over habit
- **Mastery milestone**: Last part completion,

Each milestone needs:
- Clear completion criteria
- Encouraging reward message
- Optional target days

### 3. Schedule Types

**IMPORTANT**: Every habit must have at least one schedule type, but can have both:
- **Low-Level Schedule**: For repetitive, routine habits
- **High-Level Schedule**: For progressive, phase-based habits
- **Both Schedules**: For complex habits that need both routine and progression

#### Low-Level Schedule (Repetitive)
Use when habit has regular, repeating patterns:

**Span Types:**
- \`daily\`: Steps have \`time\` field (HH:MM format)
- \`weekly\`: Steps have \`day\` field (mon, tue, wed, thu, fri, sat, sun)
- \`monthly\`: Steps have \`day_of_month\` field (1-31)

**Span Interval:**
- \`null\`: Repeat indefinitely
- \`number\`: Specific number of repetitions

#### High-Level Schedule (Progressive)
Use when habit has phases or progressive difficulty:
- No span/interval - just sequential steps
- Organized in phases (foundation, building, mastery)
- Each phase has duration and specific goals and completion criteria.

### 4. Step Structure
Each step must include:
- **id**: Unique identifier
- **instructions**: Clear, actionable instructions
- **feedback**: Encouraging completion message
- **duration_minutes**: Estimated time (optional)
- **difficulty**: easy/medium/hard/expert

### 5. Reminders
Generate appropriate reminders:
- **Preparation**: Before habit execution
- **Execution**: During habit time
- **Reflection**: After completion
- **Motivation**: Periodic encouragement

## Generation Guidelines

### 1. Analyze User Intent
- Extract the core habit from conversation
- Identify if it's repetitive (low-level) or progressive (high-level)
- Determine appropriate frequency and timing
- Consider user's lifestyle and constraints

### 2. Create Realistic Milestones
- Start with achievable short-term goals
- Build to medium-term consistency
- End with long-term mastery
- Make criteria specific and measurable

### 3. Design Appropriate Schedule
- **Daily habits**: Use low-level with daily span
- **Weekly habits**: Use low-level with weekly span
- **Progressive habits**: Use high-level schedule
- **Complex habits**: Use both schedules
- **Remember**: Every habit must have at least one schedule type

### 4. Include Motivation Elements
- Positive feedback for each step
- Encouraging milestone messages
- Motivational reminders
- Clear benefits and purpose

### 5. Make It Actionable
- Instructions should be specific and clear
- Include time estimates where helpful
- Provide difficulty progression

## Output Format
Always return a valid JSON object following this structure:

\`\`\`json
{
  "name": "string - The name of the habit",
  "goal": "string - Clear, specific goal for the habit",
  "category": "string - Optional category like 'health', 'productivity', 'mindfulness', etc.",
  "description": "string - Detailed description of the habit",
  "difficulty": "beginner" | "intermediate" | "advanced",
  
  "milestones": [
    {
      "id": "string - Unique identifier",
      "description": "string - What this milestone represents",
      "completion_criteria": "string - Specific criteria to complete this milestone",
      "reward_message": "string - Encouraging message when achieved",
      "target_days": "number - Optional: target days to reach this milestone"
    }
  ],
  
  "low_level_schedule": {
    "span": "string - 'daily' | 'weekly' | 'monthly' | 'yearly' | 'every-n-days' | 'every-n-weeks' | 'every-n-months'",
    "span_interval": "number | null - How many times span to repeat (null = infinite)",
    "program": [
      {
        "steps": [
          {
            "id": "string - Unique step identifier",
            "time": "string - Time in HH:MM format (for daily) or null",
            "day": "string - Day of week (for weekly) or null",
            "day_of_month": "number - Day of month (for monthly) or null",
            "day_of_year": "string - Day of year (for yearly) or null",
            "interval_days": "number - For every-n-days, how many days between",
            "instructions": "string - What the user should do",
            "feedback": "string - Encouraging message for completion",
            "duration_minutes": "number - Optional: estimated duration",
            "difficulty": "string - 'easy' | 'medium' | 'hard' | 'expert'"
          }
        ]
      }
    ]
  },
  
  "high_level_schedule": {
    "program": [
      {
        "phase": "string - Phase name like 'foundation', 'building', 'mastery'",
        "duration_weeks": "number - How long this phase lasts",
        "goal": "string - What this phase aims to achieve",
        "steps": [
          {
            "id": "string - Unique step identifier",
            "instructions": "string - What the user should do",
            "feedback": "string - Encouraging message for completion",
            "success_criteria": "string - How to know this step is complete",
            "duration_minutes": "number - Optional: estimated duration",
            "difficulty": "string - 'easy' | 'medium' | 'hard' | 'expert'"
          }
        ]
      }
    ]
  },
  
  "reminders": [
    {
      "time": "string - Time in HH:MM format",
      "message": "string - Reminder message",
      "frequency": "string - 'daily' | 'weekly' | 'monthly' | 'once'",
      "type": "string - 'preparation' | 'execution' | 'reflection' | 'motivation'",
      "days_before": "number - Optional: how many days before to remind"
    }
  ]
}
\`\`\`

## Quality Checklist
- [ ] Clear, specific habit name and goal
- [ ] At least 3 meaningful milestones
- [ ] At least one schedule type (low-level, high-level, or both)
- [ ] Realistic timing and frequency
- [ ] Encouraging feedback messages
- [ ] Proper JSON formatting
- [ ] All required fields present

Now analyze this conversation and generate a habit JSON:

${conversation}`;

        console.log(`${logPrefix} Sending request to Gemini AI`);
        
        // Generate the habit JSON using Gemini AI
        const result = await model.generateContent(systemPrompt);
        const response = await result.response;
        const habitJsonText = response.text();
        
        console.log(`${logPrefix} Received response from Gemini AI, length:`, habitJsonText.length);
        
        // Try to parse the JSON to validate it
        let habitJson;
        try {
            // Extract JSON from the response (in case there's extra text)
            const jsonMatch = habitJsonText.match(/\{[\s\S]*\}/);
            if (jsonMatch) {
                habitJson = JSON.parse(jsonMatch[0]);
            } else {
                throw new Error('No JSON found in response');
            }
        } catch (parseError) {
            console.error(`${logPrefix} Failed to parse JSON from AI response:`, parseError);
            console.error(`${logPrefix} Raw response:`, habitJsonText);
            throw new HttpsError('internal', 'Failed to generate valid habit JSON');
        }
        
        // Validate required fields
        const requiredFields = ['name', 'goal'];
        const missingFields = requiredFields.filter(field => !habitJson[field]);
        
        if (missingFields.length > 0) {
            console.error(`${logPrefix} Missing required fields:`, missingFields);
            throw new HttpsError('internal', `Generated habit JSON is missing required fields: ${missingFields.join(', ')}`);
        }
        
        // Validate that at least one schedule exists
        if (!habitJson.low_level_schedule && !habitJson.high_level_schedule) {
            console.error(`${logPrefix} No schedule found in generated habit JSON`);
            throw new HttpsError('internal', 'Generated habit JSON must have at least one schedule type');
        }
        
        // Validate milestones are in high_level_schedule (not root level)
        if (habitJson.high_level_schedule && !habitJson.high_level_schedule.milestones) {
            console.error(`${logPrefix} high_level_schedule exists but has no milestones`);
            throw new HttpsError('internal', 'high_level_schedule must contain milestones array');
        }
        
        if (habitJson.high_level_schedule?.milestones && habitJson.high_level_schedule.milestones.length === 0) {
            console.error(`${logPrefix} high_level_schedule.milestones is empty`);
            throw new HttpsError('internal', 'high_level_schedule.milestones must contain at least one milestone');
        }
        
        // Add Firebase timestamps
        const now = new Date().toISOString();
        habitJson.created_at = now;
        // start_date will be set when user adds to calendar
        
        console.log(`${logPrefix} Successfully generated habit JSON:`, {
            name: habitJson.name,
            goal: habitJson.goal,
            hasLowLevelSchedule: !!habitJson.low_level_schedule,
            hasHighLevelSchedule: !!habitJson.high_level_schedule,
            milestonesCount: habitJson.high_level_schedule?.milestones?.length || 0
        });
        
        return {
            success: true,
            habitJson: habitJson
        };
        
    } catch (error) {
        console.error(`${logPrefix} Error:`, error);
        
        if (error instanceof HttpsError) {
            throw error;
        }
        
        throw new HttpsError('internal', `Failed to generate habit JSON: ${error instanceof Error ? error.message : 'Unknown error'}`);
    }
});

