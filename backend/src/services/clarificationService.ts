import { z } from 'zod';
import { Habit } from '../schemas/habitSchema';
import { Task } from '../schemas/taskSchema';

export interface MissingField {
  path: string;
  field: string;
  required: boolean;
  description: string;
}

export interface CompletenessAnalysis {
  isComplete: boolean;
  missingFields: MissingField[];
  confidence: number; // 0-1
  extractedData: Partial<Habit> | Partial<Task>;
}

/**
 * Analyze completeness of extracted data against schema
 */
export function analyzeCompleteness(
  data: any,
  schema: z.ZodSchema,
  type: 'habit' | 'task'
): CompletenessAnalysis {
  const missingFields: MissingField[] = [];
  let extractedData: Partial<Habit> | Partial<Task> = {};

  try {
    // Try to parse with schema to get validation errors
    const result = schema.safeParse(data);

    if (result.success) {
      // Data is complete and valid
      return {
        isComplete: true,
        missingFields: [],
        confidence: 1.0,
        extractedData: result.data,
      };
    } else {
      // Extract missing fields from errors
      const errors = result.error.errors;
      extractedData = data || {};

      for (const error of errors) {
        const path = error.path.join('.');
        const field = error.path[error.path.length - 1] as string;

        // Skip if it's a nested validation issue (we'll catch the parent)
        if (error.code === 'invalid_type' && error.received === 'undefined') {
          missingFields.push({
            path,
            field,
            required: true,
            description: getFieldDescription(field, type),
          });
        }
      }

      // Calculate confidence based on completeness
      const totalRequiredFields = getRequiredFieldsCount(type);
      const missingCount = missingFields.length;
      const confidence = Math.max(0, 1 - missingCount / totalRequiredFields);

      return {
        isComplete: false,
        missingFields,
        confidence,
        extractedData,
      };
    }
  } catch (error) {
    console.error('[analyzeCompleteness] Error analyzing completeness:', error);
    return {
      isComplete: false,
      missingFields: [{ path: 'root', field: 'root', required: true, description: 'Invalid data structure' }],
      confidence: 0,
      extractedData: data || {},
    };
  }
}

/**
 * Identify missing critical fields
 */
export function identifyMissingFields(
  data: any,
  schema: z.ZodSchema,
  type: 'habit' | 'task'
): MissingField[] {
  const analysis = analyzeCompleteness(data, schema, type);
  return analysis.missingFields.filter((field) => isCriticalField(field.path, type));
}

/**
 * Generate a clarifying question for a missing field
 */
export function generateClarifyingQuestion(
  missingField: MissingField,
  context: Partial<Habit> | Partial<Task>,
  type: 'habit' | 'task'
): string {
  const field = missingField.field;
  const path = missingField.path;

  // Generate context-aware questions
  if (type === 'habit') {
    return generateHabitQuestion(field, path, context as Partial<Habit>);
  } else {
    return generateTaskQuestion(field, path, context as Partial<Task>);
  }
}

/**
 * Assess confidence score
 */
export function assessConfidence(
  data: any,
  schema: z.ZodSchema,
  type: 'habit' | 'task'
): number {
  const analysis = analyzeCompleteness(data, schema, type);
  return analysis.confidence;
}

// Helper functions

function getFieldDescription(field: string, type: 'habit' | 'task'): string {
  const descriptions: Record<string, Record<string, string>> = {
    habit: {
      name: 'The name of the habit',
      goal: 'The specific goal for this habit',
      category: 'The category (health, productivity, fitness, etc.)',
      description: 'A detailed description of the habit',
      difficulty: 'The difficulty level (beginner, intermediate, advanced)',
      'high_level_schedule.milestones': 'Milestones for tracking progress',
      'low_level_schedule.span': 'The time span (day, week, month, year)',
      'low_level_schedule.span_value': 'The span value (e.g., 1 for daily, 2 for every 2 weeks)',
      'low_level_schedule.program': 'The detailed program schedule',
    },
    task: {
      name: 'The name of the task',
      goal: 'The specific goal for this task',
      category: 'The category',
      description: 'A detailed description of the task',
      'task_schedule.steps': 'The steps to complete the task',
    },
  };

  return descriptions[type][field] || `The ${field} field`;
}

function isCriticalField(path: string, type: 'habit' | 'task'): boolean {
  const criticalFields = {
    habit: ['name', 'goal', 'difficulty', 'high_level_schedule', 'low_level_schedule'],
    task: ['name', 'goal', 'task_schedule'],
  };

  return criticalFields[type].some((field) => path.startsWith(field));
}

function getRequiredFieldsCount(type: 'habit' | 'task'): number {
  // Approximate count of required fields
  return type === 'habit' ? 15 : 8;
}

function generateHabitQuestion(
  field: string,
  path: string,
  context: Partial<Habit>
): string {
  const questions: Record<string, string> = {
    name: "What would you like to name this habit?",
    goal: "What's your main goal with this habit?",
    category: "What category does this habit fall into? (e.g., health, productivity, fitness, mindfulness)",
    description: "Can you describe what this habit involves in more detail?",
    difficulty: "What's your experience level with this type of habit? (beginner, intermediate, or advanced)",
    'high_level_schedule.milestones': "What milestones would you like to track? (e.g., 7 days, 30 days, 90 days)",
    'low_level_schedule.span': "How often do you want to do this habit? (daily, weekly, monthly, or yearly)",
    'low_level_schedule.span_value': "How many times per period? (e.g., 1 for daily, 2 for every 2 weeks)",
    'low_level_schedule.habit_repeat_count': "How many times should this habit program repeat? (or leave infinite)",
    'low_level_schedule.program': "What specific activities or steps should be included in this habit?",
  };

  // Try to find a matching question
  for (const [key, question] of Object.entries(questions)) {
    if (path.includes(key) || field === key.split('.').pop()) {
      return question;
    }
  }

  // Default question
  return `Could you provide more information about ${field}?`;
}

function generateTaskQuestion(
  field: string,
  path: string,
  context: Partial<Task>
): string {
  const questions: Record<string, string> = {
    name: "What would you like to name this task?",
    goal: "What's your main goal with this task?",
    category: "What category does this task fall into?",
    description: "Can you describe what this task involves in more detail?",
    'task_schedule.steps': "What are the steps needed to complete this task?",
  };

  // Check for step-specific questions
  if (path.includes('steps')) {
    if (path.includes('date')) {
      return "When should this step be completed? (provide a date in YYYY-MM-DD format, or leave blank if no specific date)";
    }
    if (path.includes('time')) {
      return "What time should this step be completed? (provide time in HH:MM format)";
    }
    if (path.includes('title')) {
      return "What should this step be called?";
    }
    return "Can you provide more details about this step?";
  }

  // Try to find a matching question
  for (const [key, question] of Object.entries(questions)) {
    if (path.includes(key) || field === key.split('.').pop()) {
      return question;
    }
  }

  // Default question
  return `Could you provide more information about ${field}?`;
}

