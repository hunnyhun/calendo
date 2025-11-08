import { z } from 'zod';

// Time format validation (HH:MM)
const timeFormatRegex = /^([0-1][0-9]|2[0-3]):[0-5][0-9]$/;
const timeSchema = z.string().regex(timeFormatRegex).nullable();

// Day of week enum
const dayOfWeekSchema = z.enum([
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
]);

// Day of month enum
const dayOfMonthSchema = z.enum([
  'start_of_month',
  '1',
  '2',
  '3',
  '4',
  '5',
  '6',
  '7',
  '8',
  '9',
  '10',
  '11',
  '12',
  '13',
  '14',
  '15',
  '16',
  '17',
  '18',
  '19',
  '20',
  '21',
  '22',
  '23',
  '24',
  '25',
  '26',
  '27',
  '28',
  'end_of_month',
]);

// Difficulty enum
const difficultySchema = z.enum(['beginner', 'intermediate', 'advanced']);

// Completion criteria enum
const completionCriteriaSchema = z.enum([
  'streak_of_days',
  'streak_of_weeks',
  'streak_of_months',
  'percentage',
]);

// Span enum
const spanSchema = z.enum(['day', 'week', 'month', 'year']);

// Milestone schema
const milestoneSchema = z.object({
  index: z.number().int().min(0),
  description: z.string(),
  completion_criteria: completionCriteriaSchema,
  completion_criteria_point: z.number(),
  reward_message: z.string(),
});

// High-level schedule schema
const highLevelScheduleSchema = z.object({
  milestones: z.array(milestoneSchema).min(1),
});

// Reminder schema (used in multiple places)
const reminderSchema = z.object({
  time: timeSchema,
  message: z.string().nullable(),
});

// Day content step schema
const dayContentStepSchema = z.object({
  step: z.string(),
  clock: timeSchema,
});

// Week content step schema
const weekContentStepSchema = z.object({
  step: z.string(),
  day: dayOfWeekSchema,
});

// Month content step schema
const monthContentStepSchema = z.object({
  step: z.string(),
  day: dayOfMonthSchema,
});

// Days indexed schema
const daysIndexedSchema = z.object({
  index: z.number().int().min(1), // Starts at 1, not 0
  title: z.string(),
  content: z.array(dayContentStepSchema).min(1),
  reminders: z.array(reminderSchema),
});

// Weeks indexed schema
const weeksIndexedSchema = z.object({
  index: z.number().int().min(1), // Starts at 1, not 0
  title: z.string(),
  description: z.string(),
  content: z.array(weekContentStepSchema).min(1),
  reminders: z.array(reminderSchema),
});

// Months indexed schema
const monthsIndexedSchema = z.object({
  index: z.number().int().min(1), // Starts at 1, not 0
  title: z.string(),
  description: z.string(),
  content: z.array(monthContentStepSchema).min(1),
  reminders: z.array(reminderSchema),
});

// Program schema
const programSchema = z.object({
  days_indexed: z.array(daysIndexedSchema),
  weeks_indexed: z.array(weeksIndexedSchema),
  months_indexed: z.array(monthsIndexedSchema),
});

// Low-level schedule schema with custom validation
const lowLevelScheduleBase = z.object({
  span: spanSchema,
  span_value: z.number().int().positive(),
  habit_schedule: z.number().int().positive().nullable(),
  habit_repeat_count: z.number().int().positive().nullable(),
  program: z.array(programSchema).min(1),
});

const lowLevelScheduleSchema = lowLevelScheduleBase.refine(
  (data: z.infer<typeof lowLevelScheduleBase>) => {
      // If both are null, it's infinite (valid)
      if (data.habit_repeat_count === null && data.habit_schedule === null) {
        return true;
      }
      // If habit_repeat_count is set, habit_schedule should be calculated
      if (data.habit_repeat_count !== null && data.habit_schedule !== null) {
        // Calculate expected habit_schedule
        let expectedDays = 0;
        switch (data.span) {
          case 'day':
            expectedDays = data.habit_repeat_count * data.span_value * 1;
            break;
          case 'week':
            expectedDays = data.habit_repeat_count * data.span_value * 7;
            break;
          case 'month':
            expectedDays = data.habit_repeat_count * data.span_value * 30; // Approximate
            break;
          case 'year':
            expectedDays = data.habit_repeat_count * data.span_value * 365; // Approximate
            break;
        }
        // Allow some tolerance for approximation (within 5 days)
        return Math.abs(data.habit_schedule - expectedDays) <= 5;
      }
      return true;
    },
    {
      message:
        'habit_schedule must be calculated from habit_repeat_count × span × span_value (converted to days)',
    }
  );

// Main habit schema
export const habitSchema = z.object({
  name: z.string().min(1),
  goal: z.string().min(1),
  category: z.string().min(1),
  description: z.string().min(1),
  difficulty: difficultySchema,
  high_level_schedule: highLevelScheduleSchema,
  low_level_schedule: lowLevelScheduleSchema,
});

// Type export for TypeScript
export type Habit = z.infer<typeof habitSchema>;
export type Milestone = z.infer<typeof milestoneSchema>;
export type HighLevelSchedule = z.infer<typeof highLevelScheduleSchema>;
export type LowLevelSchedule = z.infer<typeof lowLevelScheduleSchema>;
export type Program = z.infer<typeof programSchema>;

