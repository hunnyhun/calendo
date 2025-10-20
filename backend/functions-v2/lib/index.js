"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.sendHabitReminderTaskHandler = exports.scheduleHabitReminders = exports.generateHabitJson = exports.updateUserProfile = exports.deleteAccountAndData = exports.getCustomAuthTokenForAnonymousId = exports.sendNotificationTaskHandler = exports.scheduleDailyQuoteTasks = exports.processChatMessageV2 = exports.getTasksV2 = exports.getHabitsV2 = exports.getChatHistoryV2 = void 0;
const app_1 = require("firebase-admin/app");
const firestore_1 = require("firebase-admin/firestore");
const auth_1 = require("firebase-admin/auth");
const https_1 = require("firebase-functions/v2/https");
const scheduler_1 = require("firebase-functions/v2/scheduler");
const generative_ai_1 = require("@google/generative-ai");
const params_1 = require("firebase-functions/params");
const messaging_1 = require("firebase-admin/messaging");
const tasks_1 = require("@google-cloud/tasks");
// Define the Gemini API key secret with a different name to avoid conflicts
const geminiSecretKey = (0, params_1.defineSecret)('GEMINI_SECRET_KEY');
// Rule: Always add debug logs
console.log('🚀 Cloud Functions V2 initialized');
// Initialize Firebase Admin with application default credentials
// This is safer than using a service account key file
const app = (0, app_1.initializeApp)();
console.log('🔥 Firebase Admin initialized', { appName: app.name });
// Get Firestore instance
const db = (0, firestore_1.getFirestore)();
console.log('📊 Firestore initialized');
// Get Messaging instance
const messaging = (0, messaging_1.getMessaging)();
console.log('📱 Firebase Messaging initialized');
// Get Auth instance
const auth = (0, auth_1.getAuth)();
console.log('🔑 Firebase Auth Admin initialized');
// Initialize Cloud Tasks Client
const tasksClient = new tasks_1.CloudTasksClient();
const project = process.env.GCLOUD_PROJECT;
const location = 'us-central1';
const queue = 'daily-quote-notifications';
// Construct the fully qualified queue name.
const parent = tasksClient.queuePath(project || '', location, queue);
console.log('✅ Cloud Tasks Client initialized for queue:', parent);
// Function to ensure queue exists
async function ensureQueueExists() {
    try {
        // Check if queue exists
        await tasksClient.getQueue({ name: parent });
        console.log('✅ Queue exists:', parent);
        return true;
    }
    catch (error) {
        if (error.code === 5) { // NOT_FOUND
            console.log('⚠️ Queue does not exist, creating it:', parent);
            try {
                const locationPath = tasksClient.locationPath(project || '', location);
                await tasksClient.createQueue({
                    parent: locationPath,
                    queue: {
                        name: parent,
                        retryConfig: {
                            maxAttempts: 3,
                            maxRetryDuration: { seconds: 600 }, // 10 minutes
                            minBackoff: { seconds: 60 }, // 1 minute
                            maxBackoff: { seconds: 300 }, // 5 minutes
                            maxDoublings: 5
                        },
                        rateLimits: {
                            maxDispatchesPerSecond: 10,
                            maxBurstSize: 100,
                            maxConcurrentDispatches: 50
                        }
                    }
                });
                console.log('✅ Queue created successfully:', parent);
                // Wait a moment for queue to fully initialize
                await new Promise(resolve => setTimeout(resolve, 2000));
                return true;
            }
            catch (createError) {
                console.error('❌ Failed to create queue:', createError);
                return false;
            }
        }
        else {
            console.error('❌ Error checking queue existence:', error);
            return false;
        }
    }
}
// --- Rate Limiting Constants ---
const IP_RATE_LIMIT_WINDOW_SECONDS = 60; // 1 minute
const IP_RATE_LIMIT_MAX_REQUESTS = 30; // Max requests per window per IP
async function getUserProfile(uid) {
    try {
        const doc = await db.collection('users').doc(uid).get();
        const data = doc.data();
        if (!data || !data.profile)
            return null;
        return data.profile;
    }
    catch (e) {
        console.error('[getUserProfile] Failed to fetch profile for', uid, e);
        return null;
    }
}
function buildUserContextPrompt(profile) {
    if (!profile)
        return '';
    const parts = [];
    if (profile.name)
        parts.push(`User name: ${profile.name}`);
    if (typeof profile.age === 'number')
        parts.push(`User age: ${profile.age}`);
    if (profile.gender)
        parts.push(`Gender: ${profile.gender}`);
    if (profile.experienceLevel)
        parts.push(`Experience level: ${profile.experienceLevel}`);
    if (profile.preferredTone)
        parts.push(`Preferred tone: ${profile.preferredTone}`);
    if (profile.sufferingDuration)
        parts.push(`Suffering duration: ${profile.sufferingDuration}`);
    if (profile.goals && profile.goals.length)
        parts.push(`Goals: ${profile.goals.join(', ')}`);
    if (profile.intentions && profile.intentions.length)
        parts.push(`Intentions: ${profile.intentions.join(', ')}`);
    const header = 'Personalization Context: Use this information to tailor responses appropriately. Do not ask the user to repeat it unless necessary.';
    return [header, ...parts].filter(Boolean).join('\n');
}
// Define a limit specifically for anonymous users
const ANONYMOUS_MESSAGE_LIMIT = 2; // Limit set to 3
// System prompts for different chat modes
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
// Function to get appropriate system prompt based on chat mode
function getSystemPrompt(chatMode) {
    const validModes = ['task', 'habit'];
    if (!validModes.includes(chatMode)) {
        console.warn(`[getSystemPrompt] Invalid chat mode: ${chatMode}, defaulting to task`);
        return SYSTEM_PROMPTS.task;
    }
    return SYSTEM_PROMPTS[chatMode];
}
// Helper function to detect if we should generate a habit JSON
function shouldGenerateHabit(responseText) {
    // Look for the explicit HABITGEN flag
    const habitGenFlag = /\[HABITGEN\s*=\s*True\]/i;
    return habitGenFlag.test(responseText);
}
// Helper function to detect if we should generate a task JSON
function shouldGenerateTask(responseText) {
    // Look for the explicit TASKGEN flag
    const taskGenFlag = /\[TASKGEN\s*=\s*True\]/i;
    return taskGenFlag.test(responseText);
}
// Helper function to build conversation context for habit generation
function buildConversationContext(messages, currentMessage, currentResponse) {
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
// Internal function to generate habit JSON (reuses the logic from generateHabitJson)
async function generateHabitJsonInternal(conversation) {
    try {
        console.log('[generateHabitJsonInternal] Starting habit JSON generation');
        // Initialize Gemini AI
        const genAI = new generative_ai_1.GoogleGenerativeAI(geminiSecretKey.value());
        const model = genAI.getGenerativeModel({ model: 'gemini-2.0-flash' });
        // System prompt for habit generation (same as in generateHabitJson function)
        const systemPrompt = `You are a specialized AI agent for creating personalized habit plans. Your role is to analyze user conversations and generate comprehensive habit JSON structures that can be implemented in a habit tracking application.

## Core Requirements

### 1. Basic Habit Information
- **name**: Clear, concise habit name (2-4 words)
- **goal**: Specific, measurable goal statement
- **category**: Optional categorization (health, productivity, mindfulness, fitness, learning, etc.)
- **description**: Detailed explanation of what the habit involves
- **motivation**: Why this habit matters and its benefits

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
- \`yearly\`: Steps have \`day_of_year\` field (MM-DD format)
- \`every-n-days\`: Steps have \`interval_days\` field
- \`every-n-weeks\`: Steps have \`interval_weeks\` field
- \`every-n-months\`: Steps have \`interval_months\` field

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
  "start_date": "string - ISO 8601 timestamp (will be set when user adds to calendar)",
  "created_at": "string - ISO 8601 timestamp (generated by Firebase)",
  "category": "string - Optional category like 'health', 'productivity', 'mindfulness', etc.",
  "description": "string - Detailed description of the habit",
  "motivation": "string - Why this habit matters to the user",
  "tracking_method": "string - How progress will be measured",
  
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
    "span_interval": "number | null - How many times to repeat (null = infinite)",
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
            }
            else {
                throw new Error('No JSON found in response');
            }
        }
        catch (parseError) {
            console.error('[generateHabitJsonInternal] Failed to parse JSON from AI response:', parseError);
            console.error('[generateHabitJsonInternal] Raw response:', habitJsonText);
            return { success: false };
        }
        // Validate required fields
        const requiredFields = ['name', 'goal', 'milestones'];
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
        // Add Firebase timestamps
        const now = new Date().toISOString();
        habitJson.created_at = now;
        // start_date will be set when user adds to calendar
        console.log('[generateHabitJsonInternal] Successfully generated habit JSON:', {
            name: habitJson.name,
            goal: habitJson.goal,
            hasLowLevelSchedule: !!habitJson.low_level_schedule,
            hasHighLevelSchedule: !!habitJson.high_level_schedule,
            milestonesCount: habitJson.milestones?.length || 0
        });
        return {
            success: true,
            habitJson: habitJson
        };
    }
    catch (error) {
        console.error('[generateHabitJsonInternal] Error:', error);
        return { success: false };
    }
}
// Internal function to generate task JSON
async function generateTaskJsonInternal(conversation) {
    try {
        console.log('[generateTaskJsonInternal] Starting task JSON generation');
        // Initialize Gemini AI
        const genAI = new generative_ai_1.GoogleGenerativeAI(geminiSecretKey.value());
        const model = genAI.getGenerativeModel({ model: 'gemini-2.0-flash' });
        // System prompt for task generation
        const systemPrompt = `You are a specialized AI agent for creating task management structures. Your role is to analyze user conversations and generate task JSON structures that can be implemented in a task tracking application.

## Core Requirements

### 1. Basic Task Information
- **name**: Clear, concise task name (2-4 words)
- **description**: Detailed explanation of what the task involves
- **steps**: Array of actionable steps (optional for simple tasks)

### 2. Task Structure
Every task must have:
- Clear, actionable name
- Detailed description of what needs to be done
- Optional steps array for multi-step tasks

### 3. Steps for Multi-Step Tasks
If the task is complex, break it down into steps:
- Each step should be a single, actionable item
- Steps should be in logical order
- Keep steps simple and clear

## JSON Structure
Generate a JSON object with this exact structure:
{
  "name": "Task Name",
  "description": "What needs to be done",
  "steps": [
    {
      "description": "Step 1 description",
      "isCompleted": false
    },
    {
      "description": "Step 2 description", 
      "isCompleted": false
    }
  ]
}

## Guidelines
- Keep task names short and clear
- Make descriptions actionable and specific
- Only include steps if the task is complex enough to warrant them
- For simple tasks, use an empty steps array
- Focus on what the user needs to accomplish

## Example Outputs

Simple Task:
{
  "name": "Buy Groceries",
  "description": "Purchase weekly groceries from the store",
  "steps": []
}

Complex Task:
{
  "name": "Plan Vacation",
  "description": "Organize and plan a complete vacation trip",
  "steps": [
    {
      "description": "Research destinations and choose location",
      "isCompleted": false
    },
    {
      "description": "Book flights and accommodation",
      "isCompleted": false
    },
    {
      "description": "Create itinerary and activity list",
      "isCompleted": false
    },
    {
      "description": "Pack bags and prepare for departure",
      "isCompleted": false
    }
  ]
}

Now analyze this conversation and generate a task JSON:

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
            }
            else {
                throw new Error('No JSON found in response');
            }
        }
        catch (parseError) {
            console.error('[generateTaskJsonInternal] Failed to parse JSON from AI response:', parseError);
            console.error('[generateTaskJsonInternal] Raw response:', taskJsonText);
            return { success: false };
        }
        // Validate required fields
        const requiredFields = ['name', 'description'];
        const missingFields = requiredFields.filter(field => !taskJson[field]);
        if (missingFields.length > 0) {
            console.error('[generateTaskJsonInternal] Missing required fields:', missingFields);
            return { success: false };
        }
        // Ensure steps array exists
        if (!taskJson.steps) {
            taskJson.steps = [];
        }
        // Add Firebase timestamps
        const now = new Date().toISOString();
        taskJson.created_at = now;
        console.log('[generateTaskJsonInternal] Successfully generated task JSON:', {
            name: taskJson.name,
            description: taskJson.description,
            stepsCount: taskJson.steps?.length || 0
        });
        return {
            success: true,
            taskJson: taskJson
        };
    }
    catch (error) {
        console.error('[generateTaskJsonInternal] Error:', error);
        return { success: false };
    }
}
/**
 * Checks user authentication status for onCall functions.
 * Verifies authentication and identifies custom anonymous users via claims.
 *
 * @param {AuthData | undefined} auth The auth object from the request.
 * @throws {HttpsError('unauthenticated')} If the user is not authenticated.
 * @returns {Promise<UserAuthStatus>} An object containing the user's UID and anonymous status.
 */
async function checkUserAuthentication(auth) {
    const logPrefix = '[AuthCheck]';
    if (!auth) {
        console.error(`${logPrefix} User authentication data missing.`);
        throw new https_1.HttpsError('unauthenticated', 'User must be authenticated.');
    }
    const uid = auth.uid;
    const standardProvider = auth.token.firebase?.sign_in_provider;
    // *** MODIFICATION: Only check if provider is 'custom' ***
    const isAnonymous = standardProvider === 'custom';
    // Determine provider string for logging/debugging
    const provider = isAnonymous
        ? 'custom_provider' // Simplified logging
        : standardProvider || 'unknown'; // Use standard provider if known and not anon
    console.log(`${logPrefix} User verified:`, {
        userId: uid,
        provider: provider,
        isAnonymous: isAnonymous, // Use the calculated isAnonymous flag
    });
    return {
        uid,
        isAnonymous, // Return the calculated flag
    };
}
// Check if user has premium subscription
async function checkUserSubscription(uid) {
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
        }
        catch (error) {
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
        const yearlyProductId = 'com.hunnyhun.stoicism.yearly'; // <-- VERIFY THIS ID
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
                }
                catch (dateError) {
                    console.error(`${logPrefix} Error parsing monthly expiry date '${monthlySub.expires_date}':`, dateError);
                }
            }
            else {
                console.log(`${logPrefix} Monthly subscription entry has no expiry date.`);
            }
        }
        else {
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
                }
                catch (dateError) {
                    console.error(`${logPrefix} Error parsing yearly expiry date '${yearlySub.expires_date}':`, dateError);
                }
            }
            else {
                console.log(`${logPrefix} Yearly subscription entry has no expiry date.`);
            }
        }
        else {
            console.log(`${logPrefix} No yearly subscription entry found.`);
        }
        // If neither active subscription was found
        console.log(`${logPrefix} No active monthly or yearly subscription found based on expiry dates. User is Free.`);
        return false;
    }
    catch (error) {
        console.error(`${logPrefix} Unexpected error during subscription check for user ${uid}:`, error);
        // Default to free (false) if any unexpected error occurs during the process
        return false;
    }
}
// Check message limits for free tier users
// Modified to handle both anonymous and authenticated free users
async function checkMessageLimits(uid, isAnonymousUser) {
    try {
        const userRef = db.collection('users').doc(uid);
        let userDoc;
        // --- Anonymous User Limit Check ---
        if (isAnonymousUser) {
            console.log('🕵️ [checkMessageLimits] User is anonymous. Checking message limits.');
            let anonymousMessageCount = 0;
            try {
                userDoc = await userRef.get(); // Fetch user doc
                if (userDoc.exists) {
                    anonymousMessageCount = userDoc.data()?.anonymousMessageCount || 0;
                }
                console.log(`🕵️ [checkMessageLimits] Anonymous message count: ${anonymousMessageCount}/${ANONYMOUS_MESSAGE_LIMIT}`);
                // *** Check against the limit ***
                if (anonymousMessageCount >= ANONYMOUS_MESSAGE_LIMIT) {
                    console.log('🚫 [checkMessageLimits] Anonymous user has exceeded message limit.');
                    // *** MODIFICATION: Add details object ***
                    throw new https_1.HttpsError('resource-exhausted', 'You have reached the message limit for anonymous access. Please sign in or sign up to continue chatting.', { limitType: 'anonymous' } // Add specific detail
                    );
                }
                // If limit not reached, return true (allow message)
                console.log('✅ [checkMessageLimits] Anonymous user is within limits.');
                return true;
            }
            catch (error) {
                // Handle specific HttpsError re-throw
                if (error instanceof https_1.HttpsError) {
                    throw error; // Re-throw the specific limit error
                }
                // Handle other errors during fetch/check
                console.error('❌ [checkMessageLimits] Error fetching/checking anonymous limit:', error);
                // Decide if you want to block or allow if the check fails. Blocking is safer.
                throw new https_1.HttpsError('internal', 'Could not verify anonymous usage limits.');
            }
        }
        // --- End Anonymous User Limit Check ---
        // --- Authenticated Free User Limit Check ---
        else {
            console.log('🔢 [checkMessageLimits] Checking authenticated free user message limits for:', uid);
            try {
                // Fetch user doc if not already fetched
                if (!userDoc) {
                    userDoc = await userRef.get();
                }
                if (userDoc && userDoc.exists) {
                    const userData = userDoc.data();
                    const messageCount = userData?.messageCount || 0;
                    const messageLimit = 5; // Free tier lifetime message limit
                    console.log('🔢 [checkMessageLimits] User lifetime message count:', messageCount, 'limit:', messageLimit);
                    if (messageCount >= messageLimit) {
                        console.log('🚫 [checkMessageLimits] Authenticated free user has exceeded lifetime message limit');
                        // *** No 'details' needed here, or use a different one if preferred ***
                        throw new https_1.HttpsError('resource-exhausted', 'You have reached the message limit for the free tier. Please upgrade to premium for unlimited messages.'
                        // No details needed, or could add { limitType: 'authenticated_free' }
                        );
                    }
                    // If limit not reached, return true
                    console.log('✅ [checkMessageLimits] Authenticated free user is within limits.');
                    return true;
                }
                // Default to allowing if no user document exists yet (first message)
                console.log('🔢 [checkMessageLimits] No existing message count found, allowing first message');
                return true; // Allow the first message which will increment the count to 1
            }
            catch (error) {
                // Handle specific HttpsError re-throw
                if (error instanceof https_1.HttpsError) {
                    throw error; // Re-throw the specific limit error
                }
                console.error('❌ [checkMessageLimits] Error checking authenticated free message limits:', error);
                // Decide on behavior. Throwing an error is safer.
                throw new https_1.HttpsError('internal', 'Could not verify authenticated usage limits.');
            }
        }
        // --- End Authenticated Free User Limit Check ---
    }
    catch (error) {
        // Handle specific HttpsError re-throw from inner blocks
        if (error instanceof https_1.HttpsError) {
            throw error; // Re-throw the specific limit error
        }
        console.error('❌ [checkMessageLimits] Unexpected error:', error);
        // Default to throwing an internal error if something unexpected happens
        throw new https_1.HttpsError('internal', 'An unexpected error occurred while checking message limits.');
    }
}
// Chat History Function (using new check)
exports.getChatHistoryV2 = (0, https_1.onCall)({
    region: 'us-central1',
    enforceAppCheck: true, // App Check enforcement enabled
}, async (request) => {
    try {
        // --- Use New Authentication Check ---
        const { uid, isAnonymous } = await checkUserAuthentication(request.auth);
        // --- End Authentication Check ---
        // --- Anonymous User Check ---
        if (isAnonymous) {
            console.log('🚫 [getChatHistoryV2] Anonymous user denied history access.');
            return [];
        }
        // --- End Anonymous User Check ---
        console.log('👤 [getChatHistoryV2] Authenticated user requesting history:', { userId: uid });
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
        }
        catch (error) {
            console.error('❌ Error fetching chat history from Firestore:', error);
            // Return empty array as fallback, log appropriately
            return [];
        }
    }
    catch (error) {
        console.error('❌ Top-level error fetching chat history:', error);
        if (error instanceof https_1.HttpsError) {
            throw error; // Re-throw HttpsErrors (like 'unauthenticated' from middleware)
        }
        // Throw a different HttpsError or a generic one for client handling
        throw new https_1.HttpsError('internal', 'Failed to fetch chat history.');
    }
});
// Get Habits Function (similar to getChatHistoryV2)
exports.getHabitsV2 = (0, https_1.onCall)({
    region: 'us-central1',
    enforceAppCheck: true,
}, async (request) => {
    try {
        // --- Use New Authentication Check ---
        const { uid, isAnonymous } = await checkUserAuthentication(request.auth);
        // --- End Authentication Check ---
        // --- Anonymous User Check ---
        if (isAnonymous) {
            console.log('🚫 [getHabitsV2] Anonymous user denied habits access.');
            return [];
        }
        // --- End Anonymous User Check ---
        console.log('👤 [getHabitsV2] Authenticated user requesting habits:', { userId: uid });
        try {
            console.log('🔍 Attempting to query Firestore habits collection for user:', uid);
            const snapshot = await db
                .collection('users')
                .doc(uid)
                .collection('habits')
                .orderBy('createdAt', 'desc')
                .get();
            console.log('✅ Firestore habits query successful with docs count:', snapshot.docs.length);
            const habits = snapshot.docs.map(doc => {
                const data = doc.data();
                // Convert Firestore timestamps to ISO strings for iOS compatibility
                const processedData = {
                    id: doc.id,
                    ...data
                };
                // Handle createdAt timestamp
                if (data.createdAt && typeof data.createdAt.toDate === 'function') {
                    processedData.createdAt = data.createdAt.toDate().toISOString();
                }
                // Handle lastReminderUpdate timestamp
                if (data.lastReminderUpdate && typeof data.lastReminderUpdate.toDate === 'function') {
                    processedData.lastReminderUpdate = data.lastReminderUpdate.toDate().toISOString();
                }
                // Handle any other timestamp fields that might exist
                if (data.updatedAt && typeof data.updatedAt.toDate === 'function') {
                    processedData.updatedAt = data.updatedAt.toDate().toISOString();
                }
                return processedData;
            });
            // Debug log
            console.log('📱 Habits fetched successfully:', {
                userId: uid,
                habitCount: habits.length
            });
            return habits;
        }
        catch (error) {
            console.error('❌ Error fetching habits from Firestore:', error);
            // Return empty array as fallback, log appropriately
            return [];
        }
    }
    catch (error) {
        console.error('❌ Top-level error fetching habits:', error);
        if (error instanceof https_1.HttpsError) {
            throw error;
        }
        throw new https_1.HttpsError('internal', 'An unexpected error occurred while fetching habits.');
    }
});
// Get Tasks Function (similar to getHabitsV2)
exports.getTasksV2 = (0, https_1.onCall)({
    region: 'us-central1',
    enforceAppCheck: true,
}, async (request) => {
    try {
        // --- Use New Authentication Check ---
        const { uid, isAnonymous } = await checkUserAuthentication(request.auth);
        // --- End Authentication Check ---
        // --- Anonymous User Check ---
        if (isAnonymous) {
            console.log('🚫 [getTasksV2] Anonymous user denied tasks access.');
            return [];
        }
        // --- End Anonymous User Check ---
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
                // Convert Firestore timestamps to ISO strings for iOS compatibility
                const processedData = {
                    id: doc.id,
                    ...data
                };
                // Handle createdAt timestamp
                if (data.createdAt && typeof data.createdAt.toDate === 'function') {
                    processedData.createdAt = data.createdAt.toDate().toISOString();
                }
                // Handle completedAt timestamp
                if (data.completedAt && typeof data.completedAt.toDate === 'function') {
                    processedData.completedAt = data.completedAt.toDate().toISOString();
                }
                // Handle deadline timestamp
                if (data.deadline && typeof data.deadline.toDate === 'function') {
                    processedData.deadline = data.deadline.toDate().toISOString();
                }
                // Handle startDate timestamp
                if (data.startDate && typeof data.startDate.toDate === 'function') {
                    processedData.startDate = data.startDate.toDate().toISOString();
                }
                // Handle steps array with timestamps
                if (data.steps && Array.isArray(data.steps)) {
                    processedData.steps = data.steps.map((step) => {
                        const processedStep = { ...step };
                        if (step.scheduledDate && typeof step.scheduledDate.toDate === 'function') {
                            processedStep.scheduledDate = step.scheduledDate.toDate().toISOString();
                        }
                        return processedStep;
                    });
                }
                return processedData;
            });
            // Debug log
            console.log('📱 Tasks fetched successfully:', {
                userId: uid,
                taskCount: tasks.length
            });
            return tasks;
        }
        catch (error) {
            console.error('❌ Error fetching tasks from Firestore:', error);
            // Return empty array as fallback, log appropriately
            return [];
        }
    }
    catch (error) {
        console.error('❌ Top-level error fetching tasks:', error);
        if (error instanceof https_1.HttpsError) {
            throw error;
        }
        throw new https_1.HttpsError('internal', 'An unexpected error occurred while fetching tasks.');
    }
});
// Generate a meaningful title for a conversation based on user message and AI response
async function generateConversationTitle(userMessage, aiResponse, chatMode = 'task') {
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
        const genAI = new generative_ai_1.GoogleGenerativeAI(apiKey);
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
    }
    catch (error) {
        console.error('❌ Error generating title:', error);
        // Create a simple title from the first few words of the user message
        const words = userMessage.split(' ').slice(0, 4);
        const fallbackTitle = words.join(' ') + (words.length > 4 ? '...' : '');
        console.log('📝 Using fallback title:', fallbackTitle);
        return fallbackTitle;
    }
}
// Chat Message Function (using new check) - Now supports streaming
exports.processChatMessageV2 = (0, https_1.onRequest)({
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
        }
        else {
            // Set up JSON headers for regular response
            res.setHeader('Content-Type', 'application/json');
        }
        // Helper function to send SSE data (only for streaming)
        const sendSSE = (type, data) => {
            if (isStreamingRequest) {
                const payload = JSON.stringify({ type, data });
                res.write(`data: ${payload}\n\n`);
            }
        };
        // Helper function to send final response
        const sendResponse = (responseData, statusCode = 200) => {
            if (isStreamingRequest) {
                sendSSE('complete', responseData);
                res.end();
            }
            else {
                res.status(statusCode).json(responseData);
            }
        };
        // Helper function to send error
        const sendError = (message, statusCode = 500) => {
            if (isStreamingRequest) {
                sendSSE('error', { message });
                res.end();
            }
            else {
                res.status(statusCode).json({ error: message });
            }
        };
        // --- Add IP Rate Limiting Check --- 
        const clientIp = req.ip || req.connection.remoteAddress;
        if (clientIp) {
            try {
                await checkAndIncrementIpRateLimit(clientIp);
            }
            catch (rateLimitError) {
                console.warn('[processChatMessageV2] Rate limit exceeded for IP:', clientIp);
                sendError('Rate limit exceeded. Please try again later.', 429);
                return;
            }
        }
        else {
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
        let uid;
        let isAnonymousUser;
        try {
            const decodedToken = await (0, auth_1.getAuth)().verifyIdToken(idToken);
            uid = decodedToken.uid;
            isAnonymousUser = decodedToken.firebase?.sign_in_provider === 'custom';
            console.log('[processChatMessageV2] User authenticated:', {
                userId: uid,
                isAnonymous: isAnonymousUser,
                provider: decodedToken.firebase?.sign_in_provider || 'unknown',
                chatMode
            });
        }
        catch (authError) {
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
        // Check if habit mode requires authenticated user (non-anonymous)
        if (chatMode === 'habit' && isAnonymousUser) {
            console.error('[processChatMessageV2] Anonymous user attempted to access habit mode');
            sendError('Habit mode requires a logged-in account. Please sign up or log in.', 403);
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
        // --- Consolidated Limit Check ---
        const isPremium = await checkUserSubscription(uid);
        console.log('💲 User subscription status:', isPremium ? 'Premium' : 'Free/Anonymous');
        let applyPremiumDelay = false;
        let premiumDailyCount = 0;
        const todaysDateStr = new Date().toISOString().split('T')[0];
        if (!isPremium) {
            try {
                await checkMessageLimits(uid, isAnonymousUser);
                console.log('✅ User is within message limits.');
            }
            catch (limitError) {
                console.log('🚫 Message limit exceeded');
                sendError(limitError.message, 429);
                return;
            }
        }
        else {
            console.log('⭐️ Premium user. Checking daily chat limits for potential slowdown.');
            try {
                const userDoc = await userRef.get();
                const userData = userDoc.data() || {};
                const countDate = userData.premiumChatCountDate;
                let currentCount = userData.premiumChatDailyCount || 0;
                if (countDate !== todaysDateStr) {
                    console.log(`[PremiumLimit] Date mismatch (${countDate} vs ${todaysDateStr}). Resetting daily count for user ${uid}.`);
                    currentCount = 0;
                }
                premiumDailyCount = currentCount;
                if (premiumDailyCount >= 100) {
                    console.warn(`[PremiumLimit] Daily limit (${premiumDailyCount}/100) reached for premium user ${uid}. Applying slowdown.`);
                    applyPremiumDelay = true;
                }
                else {
                    console.log(`[PremiumLimit] Premium user ${uid} within daily limit (${premiumDailyCount}/100).`);
                }
            }
            catch (limitCheckError) {
                console.error(`[PremiumLimit] Error checking premium daily limit for ${uid}:`, limitCheckError);
            }
        }
        // --- End Consolidated Limit Check ---
        // --- Apply Delay if Necessary --- 
        if (applyPremiumDelay) {
            const delayMs = 5000;
            console.log(`[PremiumLimit] Applying ${delayMs}ms delay for user ${uid}.`);
            await new Promise(resolve => setTimeout(resolve, delayMs));
        }
        // --- End Apply Delay ---
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
        let conversationData = { messages: [], chatMode };
        let existingTitle = undefined;
        try {
            const conversationDoc = await conversationRef.get();
            if (conversationDoc.exists) {
                const data = conversationDoc.data();
                if (data) {
                    conversationData = data;
                    existingTitle = data.title;
                    console.log('✅ Conversation document retrieved successfully. Message count:', conversationData.messages.length);
                }
                else {
                    console.log('⚠️ Conversation document exists but has no data.');
                }
            }
            else {
                console.log('ℹ️ No existing conversation document found. Will create new one.');
            }
        }
        catch (error) {
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
            const genAI = new generative_ai_1.GoogleGenerativeAI(apiKey);
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
            }
            else {
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
                    }
                    else {
                        console.warn('⚠️ Failed to generate habit JSON, continuing with regular response');
                    }
                }
                catch (error) {
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
                    }
                    else {
                        console.warn('⚠️ Failed to generate task JSON, continuing with regular response');
                    }
                }
                catch (error) {
                    console.error('❌ Error generating task JSON:', error);
                    // Continue with regular response if task generation fails
                }
            }
            // Generate title only if it's a new conversation
            if (!title) {
                console.log('📝 Generating new title for conversation');
                title = await generateConversationTitle(trimmedMessage, responseText, chatMode);
            }
            else {
                console.log('📝 Using existing title:', title);
            }
        }
        catch (error) {
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
            lastUpdated: firestore_1.FieldValue.serverTimestamp(),
            title: title,
            chatMode: chatMode
        };
        batch.set(conversationRef, conversationUpdateData, { merge: true });
        console.log('🔢 Added conversation update to batch.');
        // 2. Update User Document
        const userUpdateData = {
            lastActive: firestore_1.FieldValue.serverTimestamp()
        };
        if (isAnonymousUser) {
            userUpdateData.anonymousMessageCount = firestore_1.FieldValue.increment(1);
        }
        else if (!isPremium) {
            userUpdateData.messageCount = firestore_1.FieldValue.increment(1);
        }
        else {
            userUpdateData.premiumChatDailyCount = firestore_1.FieldValue.increment(1);
            userUpdateData.premiumChatCountDate = todaysDateStr;
        }
        batch.set(userRef, userUpdateData, { merge: true });
        console.log(`🔢 Added user count/status update to batch.`);
        // Commit the batch
        try {
            console.log('💾 Committing batch update to Firestore...');
            await batch.commit();
            console.log('✅ Batch commit successful.');
        }
        catch (error) {
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
    }
    catch (error) {
        console.error('❌ Top-level error processing message:', error);
        const errorMessage = error instanceof Error ? error.message : 'An unexpected error occurred while processing your message.';
        if (res.headersSent) {
            // If headers already sent (streaming case), write error as SSE
            res.write(`data: ${JSON.stringify({ type: 'error', data: { message: errorMessage } })}\n\n`);
            res.end();
        }
        else {
            res.status(500).json({ error: errorMessage });
        }
    }
});
// Generate a spiritual quote using Gemini based on previous messages
// Rule: The fewer lines of code is better
async function generateSpiritualQuote(previousMessages) {
    try {
        // Debug log
        console.log('🌟 Generating spiritual quote based on messages:', previousMessages.length > 0);
        // Get the API key using the defineSecret API
        const apiKey = geminiSecretKey.value();
        if (!apiKey) {
            console.error('❌ Gemini API key is not found');
            throw new Error('API key not found');
        }
        // Initialize Gemini
        const genAI = new generative_ai_1.GoogleGenerativeAI(apiKey);
        const model = genAI.getGenerativeModel({ model: 'gemini-2.0-flash' });
        // Create prompt based on whether we have previous messages
        let prompt = '';
        if (previousMessages && previousMessages.length > 0) {
            // Create a prompt that incorporates user messages
            prompt = `Based on these previous messages from a user of a spiritual app: "${previousMessages.join('" "')}",
            create a short, uplifting spiritual quote or message (max 100 characters) that would be meaningful to them. 
            The quote should be general enough to be appropriate as a daily notification. 
            Include only the quote text without quotation marks or attribution.`;
            console.log('🌟 Creating personalized quote based on user messages');
        }
        else {
            // Generic prompt for users without message history
            prompt = `Create a short, uplifting spiritual or biblical quote or message (max 100 characters) that would be 
            meaningful to send as a daily notification to a user of a spiritual app.
            Include only the quote text without quotation marks or attribution.`;
            console.log('🌟 Creating generic quote (no user messages available)');
        }
        // Generate response using Gemini
        console.log('🤖 Generating quote with Gemini...');
        const result = await model.generateContent(prompt);
        const quote = result.response.text().trim();
        // Ensure the quote isn't too long for a notification
        const finalQuote = quote.length > 150 ? quote.substring(0, 147) + '...' : quote;
        console.log('✅ Generated quote:', finalQuote);
        return finalQuote;
    }
    catch (error) {
        console.error('❌ Error generating quote:', error);
        return "Reflect on your spiritual journey today. Each step brings you closer to understanding.";
    }
}
// Helper: Check if a task was already scheduled today for a specific type
async function checkTaskScheduled(userId, type, userToday) {
    const scheduledMarkerRef = db.collection('users').doc(userId).collection('scheduledTasks').doc(`${userToday}_${type}`);
    try {
        const doc = await scheduledMarkerRef.get();
        if (doc.exists) {
            console.log(`[TASK SCHEDULER] Task ${type} already scheduled today (${userToday}) for user ${userId}`);
            return true;
        }
        return false;
    }
    catch (error) {
        console.error(`[TASK SCHEDULER] Error checking schedule marker for ${userId}, type ${type}:`, error);
        return false; // Default to false if check fails
    }
}
// Helper: Mark a task as scheduled for today
async function markTaskScheduled(userId, type, userToday, scheduledTime) {
    const scheduledMarkerRef = db.collection('users').doc(userId).collection('scheduledTasks').doc(`${userToday}_${type}`);
    try {
        await scheduledMarkerRef.set({
            scheduledAt: firestore_1.FieldValue.serverTimestamp(),
            scheduledFor: scheduledTime,
            status: 'scheduled'
        });
        console.log(`[TASK SCHEDULER] Marked task ${type} as scheduled for ${userId} at ${scheduledTime.toISOString()}`);
    }
    catch (error) {
        console.error(`[TASK SCHEDULER] Error marking schedule marker for ${userId}, type ${type}:`, error);
    }
}
// Scheduled Daily Quote TASK SCHEDULER - Run once per day at midnight UTC
exports.scheduleDailyQuoteTasks = (0, scheduler_1.onSchedule)({
    schedule: '0 0 * * *', // Once per day at midnight UTC
    region: 'us-central1',
    secrets: [geminiSecretKey],
    timeZone: 'UTC',
    timeoutSeconds: 300, // Increased timeout for daily batch processing
}, async (event) => {
    try {
        // Debug log
        console.log(`[TASK SCHEDULER] Starting job: ${event.jobName} at ${new Date().toISOString()}`);
        // Ensure queue exists before proceeding
        const queueReady = await ensureQueueExists();
        if (!queueReady) {
            console.error('[TASK SCHEDULER] FATAL: Could not create or access task queue. Cannot schedule tasks.');
            return;
        }
        // Placeholder - REPLACE THIS!
        const taskHandlerUrl = `https://${location}-${project}.cloudfunctions.net/sendNotificationTaskHandler`;
        console.log(`[TASK SCHEDULER] Using task handler URL: ${taskHandlerUrl}`);
        if (!taskHandlerUrl || !taskHandlerUrl.startsWith('https://')) {
            console.error('[TASK SCHEDULER] FATAL: Task handler URL is missing or invalid. Cannot schedule tasks.');
            return; // Stop if URL is missing
        }
        // Get all users
        console.log('[TASK SCHEDULER] Getting all users');
        const usersSnapshot = await db.collection('users').get();
        console.log(`[TASK SCHEDULER] Found ${usersSnapshot.size} users`);
        if (usersSnapshot.empty) {
            console.log('[TASK SCHEDULER] No users found. Ending job.');
            return;
        }
        let tasksScheduledCount = 0;
        let skippedDueToLimit = 0;
        let skippedAlreadyScheduled = 0;
        let errorsScheduling = 0;
        const FREE_QUOTE_LIFETIME_LIMIT = 4; // 4 quotes total for free users (lifetime trailer)
        const now = new Date();
        console.log(`[TASK SCHEDULER] Running daily batch at ${now.toISOString()}`);
        // --- Define Notification Windows ---
        const morningWindowStartHourLocal = 7; // 7:00 AM Local
        const morningWindowEndHourLocal = 9; // Random time between 7-9 AM
        const eveningWindowStartHourLocal = 18; // 6:00 PM Local
        const eveningWindowEndHourLocal = 20; // Random time between 6-8 PM
        for (const userDoc of usersSnapshot.docs) {
            const userId = userDoc.id;
            const userData = userDoc.data() || {};
            try {
                // --- Add check for Anonymous User --- 
                try {
                    const userRecord = await auth.getUser(userId);
                    // Skip users with no linked standard providers (likely custom anonymous)
                    if (userRecord.providerData.length === 0) {
                        console.log(`[TASK SCHEDULER] Skipping user ${userId} - Anonymous user (no providers linked).`);
                        continue; // Skip to the next user
                    }
                }
                catch (authError) {
                    // Handle cases where the user might not exist in Auth (e.g., cleanup issues)
                    if (authError.code === 'auth/user-not-found') {
                        console.warn(`[TASK SCHEDULER] User ${userId} not found in Firebase Auth. Skipping.`);
                    }
                    else {
                        console.error(`[TASK SCHEDULER] Error fetching auth record for user ${userId}:`, authError);
                    }
                    continue; // Skip user if auth check fails
                }
                // --- End Anonymous User Check ---
                // Check subscription & Limits
                const isPremium = await checkUserSubscription(userId);
                if (isPremium) {
                    // For subscribed users: Always eligible (we schedule 2 quotes per day)
                    console.log(`[TASK SCHEDULER] Premium user ${userId} is eligible for daily quotes.`);
                }
                else {
                    // For free users: Check lifetime limit
                    const lifetimeQuoteCount = userData.lifetimeQuoteCount || 0;
                    if (lifetimeQuoteCount >= FREE_QUOTE_LIFETIME_LIMIT) {
                        console.log(`[TASK SCHEDULER] Skipping free user ${userId} - Lifetime limit reached (${lifetimeQuoteCount}/${FREE_QUOTE_LIFETIME_LIMIT}).`);
                        skippedDueToLimit++;
                        continue;
                    }
                    console.log(`[TASK SCHEDULER] Free user ${userId} within lifetime limit (${lifetimeQuoteCount}/${FREE_QUOTE_LIFETIME_LIMIT}).`);
                }
                // Determine User's Local Timezone Info (check ALL devices, not just notification-enabled)
                let userTimeZoneOffset = 0;
                const devicesSnapshot = await db.collection('users')
                    .doc(userId)
                    .collection('devices')
                    // Get ANY device with timezone info (notification permission not required)
                    .where('timeZoneOffset', '!=', null)
                    .limit(1)
                    .get();
                if (!devicesSnapshot.empty) {
                    userTimeZoneOffset = devicesSnapshot.docs[0].data().timeZoneOffset || 0;
                    console.log(`[TASK SCHEDULER] Found timezone offset ${userTimeZoneOffset} for user ${userId} from device ${devicesSnapshot.docs[0].id.substring(0, 10)}...`);
                }
                else {
                    // No device data found - this could happen for several reasons:
                    // 1. User never opened the app after authentication
                    // 2. FCM token generation failed
                    // 3. Device registration failed silently
                    // 4. User is using a web client or unsupported platform
                    console.log(`[TASK SCHEDULER] No device data found for user ${userId}. Using UTC timezone.`);
                    console.log(`[TASK SCHEDULER] Possible reasons: FCM token not generated, device registration failed, or web-only user.`);
                    userTimeZoneOffset = 0; // Default to UTC
                    // Note: Quote will still be saved to dailyQuotes collection for in-app access
                    // but no push notification will be sent (handled later in the flow)
                }
                // Calculate user's local date for today
                const userDate = new Date(now.getTime() + userTimeZoneOffset * 3600000);
                const userToday = userDate.toISOString().split('T')[0]; // YYYY-MM-DD
                console.log(`[TASK SCHEDULER] Processing user ${userId} for date: ${userToday}, timezone offset: ${userTimeZoneOffset}`);
                // Schedule both morning and evening tasks for the day
                const tasksToSchedule = [
                    { type: 'notification_morning', windowStart: morningWindowStartHourLocal, windowEnd: morningWindowEndHourLocal },
                    { type: 'notification_evening', windowStart: eveningWindowStartHourLocal, windowEnd: eveningWindowEndHourLocal }
                ];
                for (const taskConfig of tasksToSchedule) {
                    const { type, windowStart, windowEnd } = taskConfig;
                    // Check if already scheduled for today
                    const alreadyScheduled = await checkTaskScheduled(userId, type, userToday);
                    if (alreadyScheduled) {
                        console.log(`[TASK SCHEDULER] ${type} already scheduled for user ${userId} on ${userToday}`);
                        skippedAlreadyScheduled++;
                        continue;
                    }
                    // --- Calculate Random Send Time ---
                    const randomMinutes = Math.floor(Math.random() * (windowEnd - windowStart) * 60); // Random within window
                    const sendDate = new Date(userDate); // Use user's local date object
                    // Set hour to the start of the window, then add random minutes
                    sendDate.setHours(windowStart, 0, 0, 0);
                    sendDate.setMinutes(sendDate.getMinutes() + randomMinutes);
                    // Convert to UTC for Cloud Tasks
                    const sendDateUTC = new Date(sendDate.getTime() - userTimeZoneOffset * 3600000);
                    // Ensure calculated time is not in the past relative to now
                    const minScheduleTime = new Date(now.getTime() + 5 * 60 * 1000);
                    if (sendDateUTC.getTime() < minScheduleTime.getTime()) {
                        console.log(`[TASK SCHEDULER] Calculated send time for ${userId} ${type} (${sendDateUTC.toISOString()}) is in the past. Scheduling for 5 mins from now.`);
                        sendDateUTC.setTime(minScheduleTime.getTime());
                    }
                    // Check if this will reach the user's limit (for free users only)
                    let limitReachedByThisQuote = false;
                    if (!isPremium) {
                        // For free users: check if this will be their last quote
                        const currentLifetimeCount = userData.lifetimeQuoteCount || 0;
                        const newLifetimeCount = currentLifetimeCount + 1;
                        if (newLifetimeCount >= FREE_QUOTE_LIFETIME_LIMIT) {
                            limitReachedByThisQuote = true;
                            console.log(`[TASK SCHEDULER] Free user ${userId} will reach lifetime limit with ${type} task (${newLifetimeCount}/${FREE_QUOTE_LIFETIME_LIMIT}).`);
                        }
                    }
                    // Premium users never reach a limit (as long as they stay subscribed)
                    // --- Generate Quote ---
                    // Fetch history (simplified - you might want more context)
                    let userMessages = [];
                    try {
                        const convos = await db.collection('users').doc(userId).collection('conversations')
                            .orderBy('lastUpdated', 'desc').limit(1).get();
                        if (!convos.empty && convos.docs[0].data()?.messages) {
                            userMessages = convos.docs[0].data().messages
                                .filter((m) => m.role === 'user').map((m) => m.content).slice(0, 3);
                        }
                    }
                    catch (histError) {
                        console.error(`Error fetching history for quote gen for ${userId}`, histError);
                    }
                    let quote = `${type === 'notification_morning' ? 'Good morning!' : 'Good evening!'} May your day be blessed.`; // Default
                    try {
                        quote = await generateSpiritualQuote(userMessages);
                    }
                    catch (quoteError) {
                        console.error(`Error generating quote for ${userId}`, quoteError);
                    }
                    // --- Create Cloud Task ---
                    const payload = {
                        userId: userId,
                        quote: quote,
                        sendType: type,
                        limitReached: limitReachedByThisQuote
                    };
                    const task = {
                        httpRequest: {
                            httpMethod: 'POST',
                            url: taskHandlerUrl,
                            body: Buffer.from(JSON.stringify(payload)).toString('base64'),
                            headers: {
                                'Content-Type': 'application/json',
                            },
                        },
                        scheduleTime: {
                            seconds: Math.floor(sendDateUTC.getTime() / 1000)
                        }
                    };
                    try {
                        console.log(`[TASK SCHEDULER] Creating ${type} task for user ${userId}, scheduled for ${sendDateUTC.toISOString()}`);
                        const [response] = await tasksClient.createTask({ parent: parent, task: task });
                        console.log(`[TASK SCHEDULER] Task ${response.name} created successfully.`);
                        tasksScheduledCount++;
                        // Mark as scheduled in Firestore AFTER successful task creation
                        await markTaskScheduled(userId, type, userToday, sendDateUTC);
                        console.log(`[TASK SCHEDULER] ${type} task created successfully for user ${userId}.`);
                    }
                    catch (error) {
                        console.error(`[TASK SCHEDULER] Failed to create ${type} task for user ${userId}:`, error);
                        // If it's a queue not found error, try to recreate the queue and retry once
                        if (error.code === 5 && error.details?.includes('Queue does not exist')) {
                            console.log(`[TASK SCHEDULER] Queue not found error detected, attempting to recreate queue and retry for user ${userId}`);
                            const queueRecreated = await ensureQueueExists();
                            if (queueRecreated) {
                                try {
                                    console.log(`[TASK SCHEDULER] Retrying task creation for user ${userId} after queue recreation`);
                                    const [retryResponse] = await tasksClient.createTask({ parent: parent, task: task });
                                    console.log(`[TASK SCHEDULER] Retry successful - Task ${retryResponse.name} created.`);
                                    tasksScheduledCount++;
                                    await markTaskScheduled(userId, type, userToday, sendDateUTC);
                                    console.log(`[TASK SCHEDULER] ${type} task created successfully for user ${userId} on retry.`);
                                }
                                catch (retryError) {
                                    console.error(`[TASK SCHEDULER] Retry also failed for user ${userId}:`, retryError);
                                    errorsScheduling++;
                                }
                            }
                            else {
                                console.error(`[TASK SCHEDULER] Could not recreate queue for retry, skipping user ${userId}`);
                                errorsScheduling++;
                            }
                        }
                        else {
                            errorsScheduling++;
                        }
                    }
                } // End task loop
            }
            catch (userError) {
                console.error(`[TASK SCHEDULER] Error processing user ${userId}:`, userError);
                errorsScheduling++; // Count general processing errors too
            }
        } // End user loop
        console.log('[TASK SCHEDULER] Completed job:', {
            usersProcessed: usersSnapshot.size,
            tasksScheduled: tasksScheduledCount,
            skippedAlreadyScheduled: skippedAlreadyScheduled,
            skippedDueToLimit: skippedDueToLimit,
            errorsScheduling: errorsScheduling
        });
    }
    catch (error) {
        console.error('[TASK SCHEDULER] Fatal error in scheduled job:', error);
        throw error; // Allow the job to report failure
    }
});
exports.sendNotificationTaskHandler = (0, https_1.onRequest)({
    region: 'us-central1',
    // Ensure this function can be invoked by Cloud Tasks
    // You might need to configure IAM permissions separately
    // Consider adding memory/cpu options if needed
}, async (req, res) => {
    // TODO: Add verification to ensure the request comes from Cloud Tasks
    // e.g., Check for specific headers or OIDC token validation
    // See: https://cloud.google.com/functions/docs/securing/authenticating#validating_tokens
    const logPrefix = '[TASK HANDLER]';
    console.log(`${logPrefix} Received task request at ${new Date().toISOString()}`);
    try {
        // Decode payload
        let payload;
        if (req.body.message && req.body.message.data) {
            // Structure for Pub/Sub triggered tasks if used in future
            payload = JSON.parse(Buffer.from(req.body.message.data, 'base64').toString());
            console.log(`${logPrefix} Decoded Pub/Sub payload for user: ${payload.userId}`);
        }
        else if (typeof req.body === 'string') {
            // Structure for direct HTTP POST with base64 body
            payload = JSON.parse(Buffer.from(req.body, 'base64').toString());
            console.log(`${logPrefix} Decoded HTTP Base64 payload for user: ${payload.userId}`);
        }
        else if (req.body && typeof req.body === 'object' && req.body.userId) {
            // Structure for direct HTTP POST with JSON body (if Content-Type was set correctly)
            payload = req.body;
            console.log(`${logPrefix} Decoded HTTP JSON payload for user: ${payload.userId}`);
        }
        else {
            console.error(`${logPrefix} Invalid payload structure:`, req.body);
            res.status(400).send('Bad Request: Invalid payload');
            return;
        }
        const { userId, quote, sendType, limitReached } = payload;
        if (!userId || !quote || !sendType) {
            console.error(`${logPrefix} Invalid payload content: Missing fields`, payload);
            res.status(400).send('Bad Request: Missing fields in payload');
            return;
        }
        console.log(`${logPrefix} Processing task for user ${userId}, type: ${sendType}`);
        // Always save the quote first so it's available in-app regardless of notification permission
        let quoteId = null;
        const quotesColRef = db.collection('users').doc(userId).collection('dailyQuotes');
        try {
            const quoteRef = await quotesColRef.add({
                quote: quote,
                timestamp: firestore_1.FieldValue.serverTimestamp(),
                sentVia: 'pending',
                isFavorite: false,
                status: 'pending'
            });
            quoteId = quoteRef.id;
            console.log(`${logPrefix} Saved quote (pending) for user ${userId}, id: ${quoteId}`);
            // Increment appropriate counters ONLY after successful quote save
            try {
                const userRef = db.collection('users').doc(userId);
                const isPremium = await checkUserSubscription(userId);
                if (isPremium) {
                    // For premium users: only track total quotes received
                    await userRef.update({
                        totalQuotesReceived: firestore_1.FieldValue.increment(1)
                    });
                    console.log(`${logPrefix} Incremented totalQuotesReceived for premium user ${userId} after successful quote save`);
                }
                else {
                    // For free users: increment lifetime count
                    await userRef.update({
                        lifetimeQuoteCount: firestore_1.FieldValue.increment(1)
                    });
                    console.log(`${logPrefix} Incremented lifetimeQuoteCount for free user ${userId} after successful quote save`);
                }
            }
            catch (counterError) {
                console.error(`${logPrefix} Failed to increment quote count for ${userId}:`, counterError);
                // Quote was saved successfully, so this is less critical
            }
        }
        catch (saveError) {
            console.error(`${logPrefix} Error pre-saving quote for ${userId}:`, saveError);
            // Don't increment counter if quote save fails
        }
        // Get ALL user's devices (to ensure quote is created even without notification permission)
        const allDevicesSnapshot = await db.collection('users')
            .doc(userId)
            .collection('devices')
            .get();
        // Filter for notification-enabled devices for actual notification sending
        const enabledDevices = allDevicesSnapshot.docs.filter(doc => doc.data().notificationsEnabled === true);
        console.log(`${logPrefix} Found ${allDevicesSnapshot.size} total devices, ${enabledDevices.length} with notifications enabled for user ${userId}`);
        if (enabledDevices.length === 0) {
            console.log(`${logPrefix} No enabled devices found for user ${userId}. Recording as in-app only (but user has devices).`);
            // Update saved quote to reflect in-app generation only
            if (quoteId) {
                try {
                    await quotesColRef.doc(quoteId).update({ sentVia: 'in_app', status: 'generated_no_notification_permission' });
                }
                catch (updErr) {
                    console.error(`${logPrefix} Failed updating in-app status for quote ${quoteId}:`, updErr);
                }
            }
            res.status(200).send(`OK: Saved in-app quote for user ${userId} (${allDevicesSnapshot.size} devices, 0 enabled)`);
            return;
        }
        console.log(`${logPrefix} Found ${enabledDevices.length} notification-enabled devices for user ${userId}`);
        // Update saved quote to delivered (will attempt sending below)
        if (quoteId) {
            try {
                await quotesColRef.doc(quoteId).update({ sentVia: sendType, status: 'delivered' });
            }
            catch (updErr) {
                console.error(`${logPrefix} Failed updating delivered status for quote ${quoteId}:`, updErr);
            }
        }
        // Send notifications
        let successCount = 0;
        let errorCount = 0;
        const batchSize = 500; // FCM batch limit
        const deviceDocs = enabledDevices; // Use only notification-enabled devices
        for (let i = 0; i < deviceDocs.length; i += batchSize) {
            const batchDocs = deviceDocs.slice(i, i + batchSize);
            const messages = []; // Use any[] for flexibility with badge counts
            // Prepare messages for the batch, including badge increment and read
            for (const deviceDoc of batchDocs) {
                const deviceToken = deviceDoc.id; // Token is the doc ID
                const devicePath = deviceDoc.ref.path;
                // Atomically increment badge count
                try {
                    await db.doc(devicePath).update({ badgeCount: firestore_1.FieldValue.increment(1) });
                    // Read the updated count (best effort)
                    let newBadgeCount = 1;
                    try {
                        const updatedDoc = await db.doc(devicePath).get();
                        newBadgeCount = updatedDoc.data()?.badgeCount || 1;
                    }
                    catch (readError) {
                        console.error(`${logPrefix} Failed to read badge count for ${deviceToken.substring(0, 10)}...`, readError);
                    }
                    const message = {
                        token: deviceToken,
                        notification: {
                            title: 'Your Daily Spiritual Message',
                            body: quote,
                        },
                        data: {
                            type: 'daily_quote',
                            quote: quote,
                            source: 'scheduled_task', // Indicate source
                            timestamp: new Date().toISOString(),
                            quoteId: quoteId || '',
                            badgeCount: newBadgeCount.toString(),
                            limitReached: limitReached.toString()
                        },
                        apns: {
                            headers: { 'apns-priority': '5', 'apns-push-type': 'alert' }, // Use 5 for content updates/non-urgent
                            payload: { aps: { 'content-available': 1, 'sound': 'default', 'badge': newBadgeCount, 'mutable-content': 1 } }
                        },
                        android: {
                            priority: 'normal', // Use normal for background tasks
                            notification: { sound: 'default', channelId: 'daily_quotes', priority: 'default', defaultSound: true, visibility: 'public' }
                        }
                    };
                    messages.push(message);
                }
                catch (updateError) {
                    console.error(`${logPrefix} Failed to update badge count for ${deviceToken.substring(0, 10)}...`, updateError);
                    // Decide if you should still try to send? Maybe skip this token.
                }
            } // End inner loop for message prep
            // Send the batch if messages were prepared
            if (messages.length > 0) {
                try {
                    console.log(`${logPrefix} Sending batch of ${messages.length} messages for user ${userId}`);
                    const batchResponse = await messaging.sendEach(messages);
                    successCount += batchResponse.successCount;
                    errorCount += batchResponse.failureCount;
                    console.log(`${logPrefix} Batch sent. Success: ${batchResponse.successCount}, Failure: ${batchResponse.failureCount}`);
                    // Handle failures (e.g., unregistered tokens)
                    if (batchResponse.failureCount > 0) {
                        const cleanupPromises = [];
                        batchResponse.responses.forEach((resp, idx) => {
                            if (!resp.success) {
                                const errorCode = resp.error?.code;
                                const failedToken = messages[idx].token; // Get token from original message
                                console.error(`${logPrefix} Failed to send to token ${failedToken.substring(0, 10)}... Error: ${errorCode} - ${resp.error?.message}`);
                                if (errorCode === 'messaging/registration-token-not-registered' || errorCode === 'messaging/invalid-registration-token') {
                                    console.log(`${logPrefix} Scheduling cleanup for invalid token: ${failedToken.substring(0, 10)}...`);
                                    const failedDeviceDoc = batchDocs.find(doc => doc.id === failedToken);
                                    if (failedDeviceDoc) {
                                        cleanupPromises.push(db.doc(failedDeviceDoc.ref.path).delete().catch(delErr => console.error(`Failed to delete token ${failedToken}:`, delErr)));
                                    }
                                }
                            }
                        });
                        await Promise.all(cleanupPromises);
                        console.log(`${logPrefix} Invalid token cleanup complete for batch.`);
                    }
                }
                catch (batchError) {
                    console.error(`${logPrefix} Error sending batch for user ${userId}:`, batchError);
                    // Note: If sendEach fails entirely, individual errors might not be available.
                    errorCount += messages.length; // Assume all failed if the call itself failed
                }
            }
        } // End batch loop
        console.log(`${logPrefix} Finished sending for user ${userId}. Total Success: ${successCount}, Total Errors: ${errorCount}`);
        // Mark task status in Firestore if needed (optional)
        // await db.collection('users').doc(userId).collection('scheduledTasks').doc(`${userToday}_${sendType}`).update({ status: 'completed', successCount, errorCount });
        // Respond to Cloud Tasks to acknowledge processing
        res.status(200).send(`OK: Processed ${successCount} success, ${errorCount} errors for user ${userId}`);
    }
    catch (error) {
        console.error(`${logPrefix} Fatal error processing task:`, error);
        // Respond with an error status code to signal failure to Cloud Tasks
        // This might cause Cloud Tasks to retry the task depending on queue configuration
        res.status(500).send(`Internal Server Error: ${error.message || 'Unknown error'}`);
    }
});
// ---- NEW FUNCTION: Generate Custom Token for Persistent Anonymous ID ----
exports.getCustomAuthTokenForAnonymousId = (0, https_1.onCall)({
    region: 'us-central1',
    enforceAppCheck: true, // App Check enforcement enabled
    // No secrets needed for this function
}, async (request) => {
    const logPrefix = '[CUSTOM TOKEN]';
    // --- Add IP Rate Limiting Check --- 
    const clientIp = request.rawRequest.ip;
    if (clientIp) { // Only check if IP exists
        await checkAndIncrementIpRateLimit(clientIp);
    }
    else {
        console.warn(`${logPrefix} Client IP address not found in request. Cannot apply rate limit.`);
        // Decide if you want to throw an error or allow requests without IP
    }
    // --- End IP Rate Limiting Check ---
    // --- ADD DETAILED LOGGING HERE ---
    // console.log(`${logPrefix} Received request. Full request object:`, JSON.stringify(request, null, 2)); // <-- COMMENT THIS OUT
    console.log(`${logPrefix} Received request.`); // Keep original log too
    // 1. Validate Request Data
    const persistentId = request.data.persistentId;
    if (!persistentId || typeof persistentId !== 'string' || persistentId.length < 36) { // Basic check (UUID length)
        console.error(`${logPrefix} Invalid or missing persistentId in request data:`, request.data);
        throw new https_1.HttpsError('invalid-argument', 'The function must be called with a valid persistentId string.');
    }
    console.log(`${logPrefix} Valid persistentId received: ${persistentId}`);
    // 2. Generate Custom Token
    try {
        console.log(`${logPrefix} Generating custom token for UID: ${persistentId} with anonymous claim.`);
        // *** MODIFICATION: Add developer claims ***
        const additionalClaims = { is_anonymous: true };
        const customToken = await (0, auth_1.getAuth)().createCustomToken(persistentId, additionalClaims);
        // *** END MODIFICATION ***
        console.log(`${logPrefix} Successfully generated custom token for UID: ${persistentId}`);
        return { customToken: customToken };
    }
    catch (error) {
        console.error(`${logPrefix} Error generating custom token for UID ${persistentId}:`, error);
        // Map common errors to HttpsError if needed, otherwise throw internal
        if (error.code === 'auth/invalid-argument') {
            throw new https_1.HttpsError('invalid-argument', 'The provided persistentId is invalid for Firebase Auth.');
        }
        throw new https_1.HttpsError('internal', `Failed to create custom token: ${error.message || 'Unknown error'}`);
    }
});
// --- Helper Function to Delete Collections Recursively --- 
async function deleteCollection(collectionRef, batchSize = 100) {
    const query = collectionRef.limit(batchSize);
    return new Promise((resolve, reject) => {
        deleteQueryBatch(query, resolve, reject);
    });
}
async function deleteQueryBatch(query, resolve, reject) {
    try {
        const snapshot = await query.get();
        // When there are no documents left, we are done
        if (snapshot.size === 0) {
            resolve();
            return;
        }
        // Delete documents in a batch
        const batch = db.batch();
        snapshot.docs.forEach(doc => {
            // Recursively delete subcollections first (important!)
            // For simplicity here, we assume known subcollection names.
            // A more robust solution would list subcollections dynamically.
            const subcollectionsToDelete = ['subcollection1', 'subcollection2']; // ADD ANY SPECIFIC SUBCOLLECTIONS OF THE CURRENT LEVEL IF NEEDED
            subcollectionsToDelete.forEach(subColl => {
                // Schedule deletion, but don't wait here to avoid deep nesting
                deleteCollection(doc.ref.collection(subColl)).catch(reject);
            });
            // Add the document itself to the batch delete
            batch.delete(doc.ref);
        });
        await batch.commit();
        // Recurse on the next batch
        process.nextTick(() => {
            deleteQueryBatch(query, resolve, reject);
        });
    }
    catch (error) {
        console.error("Error deleting batch: ", error);
        reject(error);
    }
}
// --- Account Deletion Function --- 
exports.deleteAccountAndData = (0, https_1.onCall)({
    region: 'us-central1',
    enforceAppCheck: true, // App Check enforcement enabled
    // Add secrets if needed for external service calls during deletion
}, async (request) => {
    const logPrefix = '[ACCOUNT DELETE]';
    console.log(`${logPrefix} Received request.`);
    // 1. Check Authentication AND Provider
    if (!request.auth) {
        console.error(`${logPrefix} User not authenticated.`);
        throw new https_1.HttpsError('unauthenticated', 'User must be authenticated to delete account.');
    }
    const uid = request.auth.uid;
    const signInProvider = request.auth.token.firebase?.sign_in_provider;
    console.log(`${logPrefix} Authenticated user: ${uid}, Provider: ${signInProvider || 'unknown'}`);
    // --- Add check for anonymous user --- 
    if (signInProvider === 'anonymous') {
        console.error(`${logPrefix} Anonymous user (${uid}) attempted account deletion. Denying.`);
        throw new https_1.HttpsError('permission-denied', 'Anonymous users cannot delete accounts. Please sign in with Google or Apple first.');
    }
    // --- End anonymous check --- 
    try {
        // Start a Firestore transaction for atomic operations where possible
        await db.runTransaction(async (transaction) => {
            console.log(`${logPrefix} Starting transaction for account deletion process`);
            const userRef = db.collection('users').doc(uid);
            // Verify user exists
            const userDoc = await transaction.get(userRef);
            if (!userDoc.exists) {
                console.warn(`${logPrefix} User document does not exist for ${uid}`);
                // Continue anyway to clean up other data
            }
            else {
                console.log(`${logPrefix} Found user document for ${uid}`);
            }
            // Mark user as being deleted (in case process fails, we know it's in progress)
            transaction.update(userRef, {
                deletionInProgress: true,
                deletionStarted: firestore_1.FieldValue.serverTimestamp()
            });
            console.log(`${logPrefix} Marked user account as being deleted`);
        });
        // Define subcollections to delete under users/{uid}
        const subcollections = [
            'conversations',
            'devices',
            'scheduledTasks',
            'dailyQuotes'
            // Add any other subcollections associated with the user
        ];
        // 2. Delete Subcollections Recursively
        console.log(`${logPrefix} Deleting subcollections for user ${uid}...`);
        const deletePromises = subcollections.map(async (subcollectionName) => {
            console.log(`${logPrefix}   - Deleting ${subcollectionName}...`);
            const subcollectionRef = db.collection('users').doc(uid).collection(subcollectionName);
            await deleteCollection(subcollectionRef);
            console.log(`${logPrefix}   - Finished deleting ${subcollectionName}.`);
        });
        // Wait for all subcollection deletions to complete
        await Promise.all(deletePromises);
        console.log(`${logPrefix} Finished deleting all subcollections.`);
        // 3. Check for and handle RevenueCat subscriptions
        const customerDoc = await db.collection('customers').doc(uid).get();
        if (customerDoc.exists && customerDoc.data()?.subscriptions) {
            console.log(`${logPrefix} Found RevenueCat customer data, checking for active subscriptions`);
            // Note: This is a placeholder. In a real implementation, you would:
            // 1. Use RevenueCat API to cancel subscriptions if possible
            // 2. Or flag the account for deletion in your backend systems
            console.log(`${logPrefix} Handling RevenueCat data completed`);
        }
        // 4. Delete Main User Document
        console.log(`${logPrefix} Deleting main user document: users/${uid}`);
        await db.collection('users').doc(uid).delete();
        console.log(`${logPrefix} Main user document deleted.`);
        // 5. Delete RevenueCat Customer Document
        console.log(`${logPrefix} Deleting RevenueCat document: customers/${uid}`);
        await db.collection('customers').doc(uid).delete().catch(error => {
            // Log error but don't fail the whole process if customer doc doesn't exist or fails
            console.warn(`${logPrefix} Could not delete customer document (may not exist):`, error);
        });
        console.log(`${logPrefix} RevenueCat customer document deleted (or did not exist).`);
        // 6. Delete any references in other collections
        // Example: Delete user data in shared collections like 'groups', 'communities', etc.
        // This is a placeholder - add actual collection cleanups as needed for your app
        console.log(`${logPrefix} Cleaning up user references in other collections`);
        // Example: Delete user's tasks in a "tasks" collection
        // const tasksSnapshot = await db.collection('tasks').where('userId', '==', uid).get();
        // const taskBatch = db.batch();
        // tasksSnapshot.docs.forEach(doc => taskBatch.delete(doc.ref));
        // await taskBatch.commit();
        // 7. Delete Firebase Storage Data if applicable
        // const storageBucket = admin.storage().bucket();
        // const userFilesPrefix = `userFiles/${uid}/`;
        // console.log(`${logPrefix} Deleting files from Storage at prefix: ${userFilesPrefix}`);
        // await storageBucket.deleteFiles({ prefix: userFilesPrefix });
        // console.log(`${logPrefix} Storage files deleted.`);
        // 8. Delete Firebase Auth User
        console.log(`${logPrefix} Deleting user from Firebase Authentication: ${uid}`);
        try {
            await auth.deleteUser(uid);
            console.log(`${logPrefix} Firebase Auth user deleted successfully.`);
        }
        catch (authError) {
            console.error(`${logPrefix} Error deleting Firebase Auth user:`, authError);
            // If we fail to delete the auth user but deleted their data, 
            // the account is essentially unusable but still exists
            throw new https_1.HttpsError('internal', 'Failed to delete authentication account after data was removed.');
        }
        // 9. Log success for audit purposes
        console.log(`${logPrefix} Account deletion completed successfully for user ${uid} at ${new Date().toISOString()}`);
        return {
            success: true,
            message: 'Account and all associated data deleted successfully.',
            timestamp: new Date().toISOString()
        };
    }
    catch (error) {
        console.error(`${logPrefix} Error deleting account for user ${uid}:`, error);
        // Try to mark the account as having a failed deletion attempt
        try {
            await db.collection('users').doc(uid).update({
                deletionFailed: true,
                deletionError: error.message || 'Unknown error',
                deletionAttemptedAt: firestore_1.FieldValue.serverTimestamp()
            });
        }
        catch (updateError) {
            console.error(`${logPrefix} Could not mark account as failed deletion:`, updateError);
        }
        // Avoid leaking internal details, throw a generic error
        throw new https_1.HttpsError('internal', `Failed to delete account: ${error.message || 'Unknown error'}`);
    }
});
// --- Update User Profile ---
exports.updateUserProfile = (0, https_1.onCall)({
    region: 'us-central1',
    enforceAppCheck: true,
}, async (request) => {
    const logPrefix = '[updateUserProfile]';
    try {
        const { uid } = await checkUserAuthentication(request.auth);
        const input = (request.data || {});
        // Basic sanitization: keep only known keys
        const allowedKeys = ['name', 'age', 'gender', 'goals', 'intentions', 'preferredTone', 'experienceLevel', 'sufferingDuration', 'hasCompletedProfileSetup'];
        const profile = {};
        for (const key of allowedKeys) {
            if (key in input) {
                profile[key] = input[key];
            }
        }
        await db.collection('users').doc(uid).set({ profile, lastActive: firestore_1.FieldValue.serverTimestamp() }, { merge: true });
        console.log(`${logPrefix} Updated profile for`, uid, profile);
        return { success: true };
    }
    catch (error) {
        console.error('[updateUserProfile] Error:', error);
        if (error instanceof https_1.HttpsError)
            throw error;
        throw new https_1.HttpsError('internal', 'Failed to update user profile');
    }
});
// --- Helper Function for IP Rate Limiting ---
async function checkAndIncrementIpRateLimit(ip) {
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
                throw new https_1.HttpsError('resource-exhausted', `Too many requests from this IP address. Please try again in ${IP_RATE_LIMIT_WINDOW_SECONDS} seconds.`, { ip: ip } // Optional details
                );
            }
            // Within limit, increment count
            console.log(`${logPrefix} Incrementing count for IP: ${ip}. New count: ${currentCount + 1}`);
            transaction.update(rateLimitRef, { count: firestore_1.FieldValue.increment(1) });
            // Allowed
        });
        console.log(`${logPrefix} IP ${ip} is within rate limits.`);
    }
    catch (error) {
        if (error instanceof https_1.HttpsError) {
            throw error; // Re-throw HttpsError (rate limit exceeded)
        }
        // Log other transaction errors but potentially allow the request?
        // Or throw a generic internal error?
        console.error(`${logPrefix} Error during rate limit transaction for IP ${ip}:`, error);
        // Decide on behavior for transaction errors. Throwing is safer.
        throw new https_1.HttpsError('internal', 'Failed to verify request rate limit.');
    }
}
// --- End Helper Function ---
// Generate Habit JSON Function
exports.generateHabitJson = (0, https_1.onCall)({
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
            throw new https_1.HttpsError('invalid-argument', 'Conversation is required and must be a string');
        }
        console.log(`${logPrefix} Conversation length:`, conversation.length);
        // Initialize Gemini AI
        const genAI = new generative_ai_1.GoogleGenerativeAI(geminiSecretKey.value());
        const model = genAI.getGenerativeModel({ model: 'gemini-2.0-flash' });
        // System prompt for habit generation
        const systemPrompt = `You are a specialized AI agent for creating personalized habit plans. Your role is to analyze user conversations and generate comprehensive habit JSON structures that can be implemented in a habit tracking application.

## Core Requirements

### 1. Basic Habit Information
- **name**: Clear, concise habit name (2-4 words)
- **goal**: Specific, measurable goal statement
- **category**: Optional categorization (health, productivity, mindfulness, fitness, learning, etc.)
- **description**: Detailed explanation of what the habit involves
- **motivation**: Why this habit matters and its benefits

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
- \`yearly\`: Steps have \`day_of_year\` field (MM-DD format)
- \`every-n-days\`: Steps have \`interval_days\` field
- \`every-n-weeks\`: Steps have \`interval_weeks\` field
- \`every-n-months\`: Steps have \`interval_months\` field

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
  "start_date": "string - ISO 8601 timestamp (will be set when user adds to calendar)",
  "created_at": "string - ISO 8601 timestamp (generated by Firebase)",
  "category": "string - Optional category like 'health', 'productivity', 'mindfulness', etc.",
  "description": "string - Detailed description of the habit",
  "motivation": "string - Why this habit matters to the user",
  "tracking_method": "string - How progress will be measured",
  
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
    "span_interval": "number | null - How many times to repeat (null = infinite)",
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
            }
            else {
                throw new Error('No JSON found in response');
            }
        }
        catch (parseError) {
            console.error(`${logPrefix} Failed to parse JSON from AI response:`, parseError);
            console.error(`${logPrefix} Raw response:`, habitJsonText);
            throw new https_1.HttpsError('internal', 'Failed to generate valid habit JSON');
        }
        // Validate required fields
        const requiredFields = ['name', 'goal', 'milestones'];
        const missingFields = requiredFields.filter(field => !habitJson[field]);
        if (missingFields.length > 0) {
            console.error(`${logPrefix} Missing required fields:`, missingFields);
            throw new https_1.HttpsError('internal', `Generated habit JSON is missing required fields: ${missingFields.join(', ')}`);
        }
        // Validate that at least one schedule exists
        if (!habitJson.low_level_schedule && !habitJson.high_level_schedule) {
            console.error(`${logPrefix} No schedule found in generated habit JSON`);
            throw new https_1.HttpsError('internal', 'Generated habit JSON must have at least one schedule type');
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
            milestonesCount: habitJson.milestones?.length || 0
        });
        return {
            success: true,
            habitJson: habitJson
        };
    }
    catch (error) {
        console.error(`${logPrefix} Error:`, error);
        if (error instanceof https_1.HttpsError) {
            throw error;
        }
        throw new https_1.HttpsError('internal', `Failed to generate habit JSON: ${error instanceof Error ? error.message : 'Unknown error'}`);
    }
});
// Schedule Habit Reminders Function
exports.scheduleHabitReminders = (0, https_1.onCall)({
    region: 'us-central1',
    enforceAppCheck: true,
}, async (request) => {
    const logPrefix = '[scheduleHabitReminders]';
    try {
        const { uid, isAnonymous } = await checkUserAuthentication(request.auth);
        if (isAnonymous) {
            throw new https_1.HttpsError('permission-denied', 'Anonymous users cannot schedule habit reminders.');
        }
        const { habitId, reminders } = request.data;
        if (!habitId || !reminders || !Array.isArray(reminders)) {
            throw new https_1.HttpsError('invalid-argument', 'habitId and reminders array are required.');
        }
        console.log(`${logPrefix} Scheduling ${reminders.length} reminders for habit ${habitId} for user ${uid}`);
        // Store reminders in Firestore for the habit
        const habitRef = db.collection('users').doc(uid).collection('habits').doc(habitId);
        const reminderTasks = [];
        for (const reminder of reminders) {
            const { time, message, frequency } = reminder;
            if (!time || !message || !frequency) {
                console.warn(`${logPrefix} Skipping invalid reminder:`, reminder);
                continue;
            }
            // Create notification tasks using existing task system
            const payload = {
                userId: uid,
                habitId: habitId,
                reminderTime: time,
                reminderMessage: message,
                reminderFrequency: frequency,
                type: 'habit_reminder'
            };
            // Calculate next reminder time
            const [hours, minutes] = time.split(':').map(Number);
            const now = new Date();
            let nextReminder = new Date();
            nextReminder.setHours(hours, minutes, 0, 0);
            // If time has passed today, schedule for tomorrow
            if (nextReminder <= now) {
                nextReminder.setDate(nextReminder.getDate() + 1);
            }
            const taskHandlerUrl = `https://${location}-${project}.cloudfunctions.net/sendHabitReminderTaskHandler`;
            const task = {
                httpRequest: {
                    httpMethod: 'POST',
                    url: taskHandlerUrl,
                    body: Buffer.from(JSON.stringify(payload)).toString('base64'),
                    headers: {
                        'Content-Type': 'application/json',
                    },
                },
                scheduleTime: {
                    seconds: Math.floor(nextReminder.getTime() / 1000)
                }
            };
            try {
                const [response] = await tasksClient.createTask({ parent: parent, task: task });
                console.log(`${logPrefix} Scheduled reminder task: ${response.name}`);
                reminderTasks.push({
                    taskName: response.name,
                    scheduledFor: nextReminder.toISOString(),
                    ...reminder
                });
            }
            catch (taskError) {
                console.error(`${logPrefix} Failed to schedule reminder task:`, taskError);
            }
        }
        // Update habit document with scheduled reminders
        await habitRef.update({
            scheduledReminders: reminderTasks,
            lastReminderUpdate: firestore_1.FieldValue.serverTimestamp()
        });
        console.log(`${logPrefix} Successfully scheduled ${reminderTasks.length} reminders for habit ${habitId}`);
        return {
            success: true,
            scheduledCount: reminderTasks.length,
            reminders: reminderTasks
        };
    }
    catch (error) {
        console.error(`${logPrefix} Error:`, error);
        if (error instanceof https_1.HttpsError)
            throw error;
        throw new https_1.HttpsError('internal', 'Failed to schedule habit reminders');
    }
});
// Habit Reminder Task Handler
exports.sendHabitReminderTaskHandler = (0, https_1.onRequest)({
    region: 'us-central1',
}, async (req, res) => {
    const logPrefix = '[HABIT_REMINDER_HANDLER]';
    console.log(`${logPrefix} Received habit reminder task request at ${new Date().toISOString()}`);
    try {
        // Decode payload similar to existing notification handler
        let payload;
        if (typeof req.body === 'string') {
            payload = JSON.parse(Buffer.from(req.body, 'base64').toString());
        }
        else if (req.body && typeof req.body === 'object') {
            payload = req.body;
        }
        else {
            console.error(`${logPrefix} Invalid payload structure:`, req.body);
            res.status(400).send('Bad Request: Invalid payload');
            return;
        }
        const { userId, habitId, reminderMessage, reminderFrequency, type } = payload;
        if (!userId || !habitId || !reminderMessage || type !== 'habit_reminder') {
            console.error(`${logPrefix} Invalid payload content:`, payload);
            res.status(400).send('Bad Request: Missing required fields');
            return;
        }
        console.log(`${logPrefix} Processing habit reminder for user ${userId}, habit ${habitId}`);
        // Get user's notification-enabled devices
        const devicesSnapshot = await db.collection('users')
            .doc(userId)
            .collection('devices')
            .where('notificationsEnabled', '==', true)
            .get();
        if (devicesSnapshot.empty) {
            console.log(`${logPrefix} No notification-enabled devices for user ${userId}`);
            res.status(200).send('OK: No devices to notify');
            return;
        }
        // Get habit details for better notification
        let habitTitle = 'Your Habit';
        try {
            const habitDoc = await db.collection('users').doc(userId).collection('habits').doc(habitId).get();
            if (habitDoc.exists) {
                habitTitle = habitDoc.data()?.title || habitTitle;
            }
        }
        catch (error) {
            console.warn(`${logPrefix} Could not fetch habit details:`, error);
        }
        // Send notifications to all enabled devices
        const messages = [];
        for (const deviceDoc of devicesSnapshot.docs) {
            const deviceToken = deviceDoc.id;
            // Increment badge count
            try {
                await deviceDoc.ref.update({ badgeCount: firestore_1.FieldValue.increment(1) });
                const updatedDoc = await deviceDoc.ref.get();
                const badgeCount = updatedDoc.data()?.badgeCount || 1;
                const message = {
                    token: deviceToken,
                    notification: {
                        title: '🎯 Habit Reminder',
                        body: reminderMessage,
                    },
                    data: {
                        type: 'habit_reminder',
                        habitId: habitId,
                        habitTitle: habitTitle,
                        message: reminderMessage,
                        timestamp: new Date().toISOString(),
                        badgeCount: badgeCount.toString()
                    },
                    apns: {
                        headers: { 'apns-priority': '10', 'apns-push-type': 'alert' },
                        payload: { aps: { 'content-available': 1, 'sound': 'default', 'badge': badgeCount } }
                    },
                    android: {
                        priority: 'high',
                        notification: {
                            sound: 'default',
                            channelId: 'habit_reminders',
                            priority: 'high',
                            defaultSound: true
                        }
                    }
                };
                messages.push(message);
            }
            catch (error) {
                console.error(`${logPrefix} Failed to prepare message for device ${deviceToken}:`, error);
            }
        }
        // Send notifications
        if (messages.length > 0) {
            try {
                const batchResponse = await messaging.sendEach(messages);
                console.log(`${logPrefix} Sent ${batchResponse.successCount} notifications, ${batchResponse.failureCount} failed`);
                // Handle failed tokens (cleanup invalid ones)
                if (batchResponse.failureCount > 0) {
                    const cleanupPromises = [];
                    batchResponse.responses.forEach((resp, idx) => {
                        if (!resp.success) {
                            const errorCode = resp.error?.code;
                            if (errorCode === 'messaging/registration-token-not-registered' ||
                                errorCode === 'messaging/invalid-registration-token') {
                                const failedToken = messages[idx].token;
                                cleanupPromises.push(db.collection('users').doc(userId).collection('devices').doc(failedToken).delete()
                                    .catch(err => console.error(`Failed to delete invalid token ${failedToken}:`, err)));
                            }
                        }
                    });
                    await Promise.all(cleanupPromises);
                }
            }
            catch (error) {
                console.error(`${logPrefix} Failed to send notifications:`, error);
                res.status(500).send('Failed to send notifications');
                return;
            }
        }
        // Schedule next reminder if it's recurring
        if (reminderFrequency === 'daily') {
            // Schedule next day's reminder
            const nextDay = new Date();
            nextDay.setDate(nextDay.getDate() + 1);
            const nextPayload = { ...payload };
            const nextTask = {
                httpRequest: {
                    httpMethod: 'POST',
                    url: req.url,
                    body: Buffer.from(JSON.stringify(nextPayload)).toString('base64'),
                    headers: { 'Content-Type': 'application/json' },
                },
                scheduleTime: {
                    seconds: Math.floor(nextDay.getTime() / 1000)
                }
            };
            try {
                await tasksClient.createTask({ parent: parent, task: nextTask });
                console.log(`${logPrefix} Scheduled next day's reminder for habit ${habitId}`);
            }
            catch (error) {
                console.error(`${logPrefix} Failed to schedule next reminder:`, error);
            }
        }
        res.status(200).send(`OK: Processed habit reminder for ${userId}`);
    }
    catch (error) {
        console.error(`${logPrefix} Fatal error:`, error);
        res.status(500).send(`Internal Server Error: ${error instanceof Error ? error.message : 'Unknown error'}`);
    }
});
//# sourceMappingURL=index.js.map