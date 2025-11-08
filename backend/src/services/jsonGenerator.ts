import { ChatGoogleGenerativeAI } from '@langchain/google-genai';
import { ChatPromptTemplate } from '@langchain/core/prompts';
import { habitSchema, Habit } from '../schemas/habitSchema';
import { taskSchema, Task } from '../schemas/taskSchema';
import { SessionState } from './sessionManager';

export interface JsonGenerationConfig {
  useFunctionCalling?: boolean;
  model: ChatGoogleGenerativeAI;
  apiKey: string;
}

export interface JsonGenerationResult {
  success: boolean;
  json?: Habit | Task;
  error?: string;
  validated: boolean;
}

/**
 * Generate habit JSON using function-calling (if enabled) or structured output
 */
export async function generateHabitJson(
  conversationContext: string,
  sessionState: SessionState,
  config: JsonGenerationConfig
): Promise<JsonGenerationResult> {
  try {
    let jsonData: any;

    if (config.useFunctionCalling) {
      // Use function-calling for deterministic JSON
      jsonData = await generateWithFunctionCalling(
        conversationContext,
        'habit',
        config
      );
    } else {
      // Use structured output with prompt
      jsonData = await generateWithStructuredOutput(
        conversationContext,
        'habit',
        config
      );
    }

    // Normalize the data before validation
    jsonData = normalizeHabitJson(jsonData);

    // Always validate with zod
    const validationResult = habitSchema.safeParse(jsonData);

    if (!validationResult.success) {
      console.error('[generateHabitJson] Validation failed:', validationResult.error);
      return {
        success: false,
        error: `Validation failed: ${validationResult.error.message}`,
        validated: false,
      };
    }

    return {
      success: true,
      json: validationResult.data,
      validated: true,
    };
  } catch (error) {
    console.error('[generateHabitJson] Error generating habit JSON:', error);
    return {
      success: false,
      error: error instanceof Error ? error.message : 'Unknown error',
      validated: false,
    };
  }
}

/**
 * Generate task JSON using function-calling (if enabled) or structured output
 */
export async function generateTaskJson(
  conversationContext: string,
  sessionState: SessionState,
  config: JsonGenerationConfig
): Promise<JsonGenerationResult> {
  try {
    let jsonData: any;

    if (config.useFunctionCalling) {
      // Use function-calling for deterministic JSON
      jsonData = await generateWithFunctionCalling(
        conversationContext,
        'task',
        config
      );
    } else {
      // Use structured output with prompt
      jsonData = await generateWithStructuredOutput(
        conversationContext,
        'task',
        config
      );
    }

    // Always validate with zod
    const validationResult = taskSchema.safeParse(jsonData);

    if (!validationResult.success) {
      console.error('[generateTaskJson] Validation failed:', validationResult.error);
      return {
        success: false,
        error: `Validation failed: ${validationResult.error.message}`,
        validated: false,
      };
    }

    return {
      success: true,
      json: validationResult.data,
      validated: true,
    };
  } catch (error) {
    console.error('[generateTaskJson] Error generating task JSON:', error);
    return {
      success: false,
      error: error instanceof Error ? error.message : 'Unknown error',
      validated: false,
    };
  }
}

/**
 * Generate JSON using function-calling
 */
async function generateWithFunctionCalling(
  conversationContext: string,
  type: 'habit' | 'task',
  config: JsonGenerationConfig
): Promise<any> {
  // Note: Function-calling with Gemini via LangChain requires specific setup
  // For now, we'll use structured output as a fallback
  // This can be enhanced when function-calling is fully supported
  
  console.log('[generateWithFunctionCalling] Using structured output fallback');
  return generateWithStructuredOutput(conversationContext, type, config);
}

/**
 * Generate JSON using structured output with detailed prompt
 */
async function generateWithStructuredOutput(
  conversationContext: string,
  type: 'habit' | 'task',
  config: JsonGenerationConfig
): Promise<any> {
  const systemPrompt = type === 'habit' 
    ? buildHabitGenerationPrompt()
    : buildTaskGenerationPrompt();

  const prompt = ChatPromptTemplate.fromMessages([
    ['system', systemPrompt],
    ['human', 'Analyze this conversation and generate the JSON:\n\n{conversation}'],
  ]);

  const chain = prompt.pipe(config.model);

  const response = await chain.invoke({
    conversation: conversationContext,
  });

  const text = response.content as string;

  // Extract JSON from response
  let jsonData: any;
  try {
    // Try to find JSON in the response
    const jsonMatch = text.match(/\{[\s\S]*\}/);
    if (jsonMatch) {
      jsonData = JSON.parse(jsonMatch[0]);
    } else {
      throw new Error('No JSON found in response');
    }
  } catch (parseError) {
    console.error('[generateWithStructuredOutput] Failed to parse JSON:', parseError);
    console.error('[generateWithStructuredOutput] Raw response:', text);
    throw new Error('Failed to parse JSON from AI response');
  }

  return jsonData;
}

/**
 * Build habit generation prompt
 */
function buildHabitGenerationPrompt(): string {
  return `You are a specialized AI agent for creating personalized habit plans. Your role is to analyze user conversations and generate comprehensive habit JSON structures.

CRITICAL REQUIREMENTS - FOLLOW EXACTLY:
1. Generate valid JSON matching the exact schema structure
2. Include ALL required fields:
   - name: string (GENERATE THIS AUTOMATICALLY based on conversation - do NOT ask user for name)
   - goal: string
   - category: string
   - description: string
   - difficulty: MUST be one of "beginner" | "intermediate" | "advanced" (NOT "easy", "medium", "hard", etc.)
   - high_level_schedule: MUST be an OBJECT with a "milestones" array property
   - low_level_schedule: MUST be an OBJECT with span, span_value, habit_schedule, habit_repeat_count, and program

IMPORTANT: Always generate a habit name automatically from the conversation context. Never ask the user for a name.

3. high_level_schedule structure (MUST be an object, NOT an array):
   {{
     "milestones": [
       {{
         "index": 0,
         "description": "string",
         "completion_criteria": "streak_of_days" | "streak_of_weeks" | "streak_of_months" | "percentage",
         "completion_criteria_point": number,
         "reward_message": "string"
       }}
     ]
   }}

4. low_level_schedule structure (MUST be an object):
   {{
     "span": "day" | "week" | "month" | "year",
     "span_value": positive integer,
     "habit_schedule": number (days) or null (if infinite),
     "habit_repeat_count": number or null (if infinite),
     "program": [  // MUST be an array, NOT an object
       {{
         "days_indexed": [],
         "weeks_indexed": [],
         "months_indexed": []
       }}
     ]
   }}

5. Program structure (program MUST be an array with one object):
   - program is an ARRAY containing ONE object
   - That object has: days_indexed (array), weeks_indexed (array), months_indexed (array)
   - days_indexed: array of OBJECTS (NOT numbers), each object has:
     * index: number (starting at 1)
     * title: string
     * content: array of OBJECTS (NOT strings), each object has: {{ step: string, clock: "00:00" | null }}
     * reminders: array
   - weeks_indexed: array of OBJECTS (NOT numbers), each object has:
     * index: number (starting at 1)
     * title: string
     * description: string
     * content: array of OBJECTS (NOT strings), each object has: {{ step: string, day: "Monday" | "Tuesday" | ... }}
     * reminders: array
   - months_indexed: array of OBJECTS (NOT numbers), each object has:
     * index: number (starting at 1)
     * title: string
     * description: string
     * content: array of OBJECTS (NOT strings), each object has: {{ step: string, day: "1" | "2" | ... }}
     * reminders: array
   
   CRITICAL: 
   - days_indexed, weeks_indexed, and months_indexed must be arrays of OBJECTS, NOT arrays of numbers!
   - content arrays must contain OBJECTS with step/clock or step/day properties, NOT strings!

6. Difficulty mapping:
   - "easy" or "simple" → "beginner"
   - "medium" or "moderate" → "intermediate"
   - "hard" or "difficult" → "advanced"
   - Always use: "beginner", "intermediate", or "advanced"

7. Milestones:
   - At least 3 milestones (index 0, 1, 2+)
   - completion_criteria: "streak_of_days" | "streak_of_weeks" | "streak_of_months" | "percentage"
   - completion_criteria_point: number
   - reward_message: string

EXAMPLE STRUCTURE:
{{
  "name": "Morning Exercise",
  "goal": "Build a daily exercise routine",
  "category": "fitness",
  "description": "Daily morning exercise routine",
  "difficulty": "beginner",
  "high_level_schedule": {{
    "milestones": [...]
  }},
  "low_level_schedule": {{
    "span": "day",
    "span_value": 1,
    "habit_schedule": null,
    "habit_repeat_count": null,
    "program": [
      {{
        "days_indexed": [...],
        "weeks_indexed": [...],
        "months_indexed": [...]
      }}
    ]
  }}
}}

OUTPUT FORMAT:
Return ONLY valid JSON, no additional text or markdown formatting.`;
}

/**
 * Build task generation prompt
 */
function buildTaskGenerationPrompt(): string {
  return `You are a specialized AI agent for creating task management structures. Your role is to analyze user conversations and generate task JSON structures.

CRITICAL REQUIREMENTS:
1. Generate valid JSON matching the exact schema structure
2. Include ALL required fields:
   - name, goal, category, description
   - task_schedule with steps array

3. For task_schedule.steps:
   - index: positive integer (starts at 1)
   - title: string
   - description: string or null
   - date: "YYYY-MM-DD" format or null
   - time: "HH:MM" format or null (only if date is set)
   - reminders: array (only valid if date is set)

4. For reminders:
   - offset: { unit: "days" | "weeks" | "months", value: positive number }
   - time: "HH:MM" format or null
   - message: string or null

OUTPUT FORMAT:
Return ONLY valid JSON, no additional text or markdown formatting.`;
}

/**
 * Normalize habit JSON to fix common issues before validation
 */
function normalizeHabitJson(jsonData: any): any {
  const normalized = { ...jsonData };

  // Fix difficulty enum values
  if (normalized.difficulty) {
    const difficulty = normalized.difficulty.toLowerCase();
    if (difficulty === 'easy' || difficulty === 'simple') {
      normalized.difficulty = 'beginner';
    } else if (difficulty === 'medium' || difficulty === 'moderate') {
      normalized.difficulty = 'intermediate';
    } else if (difficulty === 'hard' || difficulty === 'difficult' || difficulty === 'expert') {
      normalized.difficulty = 'advanced';
    }
  }

  // Fix high_level_schedule if it's an array instead of object
  if (Array.isArray(normalized.high_level_schedule)) {
    normalized.high_level_schedule = {
      milestones: normalized.high_level_schedule,
    };
  } else if (normalized.high_level_schedule && !normalized.high_level_schedule.milestones) {
    // If it's an object but doesn't have milestones, try to extract them
    if (Array.isArray(normalized.high_level_schedule)) {
      normalized.high_level_schedule = {
        milestones: normalized.high_level_schedule,
      };
    }
  }

  // Fix low_level_schedule.program if it's an object instead of array
  if (normalized.low_level_schedule) {
    if (normalized.low_level_schedule.program && !Array.isArray(normalized.low_level_schedule.program)) {
      // If program is an object, wrap it in an array
      normalized.low_level_schedule.program = [normalized.low_level_schedule.program];
    }

    // Fix program array structure
    if (normalized.low_level_schedule.program && Array.isArray(normalized.low_level_schedule.program)) {
      normalized.low_level_schedule.program = normalized.low_level_schedule.program.map((programItem: any) => {
        if (!programItem || typeof programItem !== 'object') {
          return programItem;
        }

        // Fix days_indexed if it contains numbers instead of objects
        if (programItem.days_indexed && Array.isArray(programItem.days_indexed)) {
          programItem.days_indexed = programItem.days_indexed.map((item: any, idx: number) => {
            if (typeof item === 'number') {
              // Convert number to proper object structure
              return {
                index: item,
                title: `Day ${item}`,
                content: [{ step: 'Complete habit activity', clock: null }],
                reminders: [],
              };
            }
            
            // Fix content array if it contains strings instead of objects
            if (item && typeof item === 'object' && Array.isArray(item.content)) {
              item.content = item.content.map((contentItem: any) => {
                if (typeof contentItem === 'string') {
                  return {
                    step: contentItem,
                    clock: null,
                  };
                }
                return contentItem;
              });
            }
            
            return item;
          });
        }

        // Fix weeks_indexed if it contains numbers instead of objects
        if (programItem.weeks_indexed && Array.isArray(programItem.weeks_indexed)) {
          programItem.weeks_indexed = programItem.weeks_indexed.map((item: any, idx: number) => {
            if (typeof item === 'number') {
              // Convert number to proper object structure
              return {
                index: item,
                title: `Week ${item}`,
                description: `Week ${item} activities`,
                content: [{ step: 'Complete habit activity', day: 'Monday' }],
                reminders: [],
              };
            }
            
            // Fix content array if it contains strings instead of objects
            if (item && typeof item === 'object' && Array.isArray(item.content)) {
              item.content = item.content.map((contentItem: any) => {
                if (typeof contentItem === 'string') {
                  return {
                    step: contentItem,
                    day: 'Monday', // Default day
                  };
                }
                return contentItem;
              });
            }
            
            return item;
          });
        }

        // Fix months_indexed if it contains numbers instead of objects
        if (programItem.months_indexed && Array.isArray(programItem.months_indexed)) {
          programItem.months_indexed = programItem.months_indexed.map((item: any, idx: number) => {
            if (typeof item === 'number') {
              // Convert number to proper object structure
              return {
                index: item,
                title: `Month ${item}`,
                description: `Month ${item} activities`,
                content: [{ step: 'Complete habit activity', day: '1' }],
                reminders: [],
              };
            }
            
            // Fix content array if it contains strings instead of objects
            if (item && typeof item === 'object' && Array.isArray(item.content)) {
              item.content = item.content.map((contentItem: any) => {
                if (typeof contentItem === 'string') {
                  return {
                    step: contentItem,
                    day: '1', // Default day
                  };
                }
                return contentItem;
              });
            }
            
            return item;
          });
        }

        return programItem;
      });
    }
  }

  return normalized;
}

/**
 * Validate JSON against schema
 */
export function validateJson(
  jsonData: any,
  type: 'habit' | 'task'
): { valid: boolean; error?: string; data?: Habit | Task } {
  // Normalize before validation
  const normalized = type === 'habit' ? normalizeHabitJson(jsonData) : jsonData;
  
  const schema = type === 'habit' ? habitSchema : taskSchema;
  const result = schema.safeParse(normalized);

  if (result.success) {
    return {
      valid: true,
      data: result.data,
    };
  } else {
    return {
      valid: false,
      error: result.error.message,
    };
  }
}

