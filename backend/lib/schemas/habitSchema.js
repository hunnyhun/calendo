"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.habitSchema = void 0;
const zod_1 = require("zod");
// Time format validation (HH:MM)
const timeFormatRegex = /^([0-1][0-9]|2[0-3]):[0-5][0-9]$/;
const timeSchema = zod_1.z.string().regex(timeFormatRegex).nullable();
// Day of week enum
const dayOfWeekSchema = zod_1.z.enum([
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
]);
// Day of month enum
const dayOfMonthSchema = zod_1.z.enum([
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
const difficultySchema = zod_1.z.enum(['beginner', 'intermediate', 'advanced']);
// Completion criteria enum
const completionCriteriaSchema = zod_1.z.enum([
    'streak_of_days',
    'streak_of_weeks',
    'streak_of_months',
    'percentage',
]);
// Span enum
const spanSchema = zod_1.z.enum(['day', 'week', 'month', 'year']);
// Milestone schema
const milestoneSchema = zod_1.z.object({
    index: zod_1.z.number().int().min(0),
    description: zod_1.z.string(),
    completion_criteria: completionCriteriaSchema,
    completion_criteria_point: zod_1.z.number(),
    reward_message: zod_1.z.string(),
});
// High-level schedule schema
const highLevelScheduleSchema = zod_1.z.object({
    milestones: zod_1.z.array(milestoneSchema).min(1),
});
// Reminder schema (used in multiple places)
const reminderSchema = zod_1.z.object({
    time: timeSchema,
    message: zod_1.z.string().nullable(),
});
// Day content step schema
const dayContentStepSchema = zod_1.z.object({
    step: zod_1.z.string(),
    clock: timeSchema,
});
// Week content step schema
const weekContentStepSchema = zod_1.z.object({
    step: zod_1.z.string(),
    day: dayOfWeekSchema,
});
// Month content step schema
const monthContentStepSchema = zod_1.z.object({
    step: zod_1.z.string(),
    day: dayOfMonthSchema,
});
// Days indexed schema
const daysIndexedSchema = zod_1.z.object({
    index: zod_1.z.number().int().min(1), // Starts at 1, not 0
    title: zod_1.z.string(),
    content: zod_1.z.array(dayContentStepSchema).min(1),
    reminders: zod_1.z.array(reminderSchema),
});
// Weeks indexed schema
const weeksIndexedSchema = zod_1.z.object({
    index: zod_1.z.number().int().min(1), // Starts at 1, not 0
    title: zod_1.z.string(),
    description: zod_1.z.string(),
    content: zod_1.z.array(weekContentStepSchema).min(1),
    reminders: zod_1.z.array(reminderSchema),
});
// Months indexed schema
const monthsIndexedSchema = zod_1.z.object({
    index: zod_1.z.number().int().min(1), // Starts at 1, not 0
    title: zod_1.z.string(),
    description: zod_1.z.string(),
    content: zod_1.z.array(monthContentStepSchema).min(1),
    reminders: zod_1.z.array(reminderSchema),
});
// Program schema
const programSchema = zod_1.z.object({
    days_indexed: zod_1.z.array(daysIndexedSchema),
    weeks_indexed: zod_1.z.array(weeksIndexedSchema),
    months_indexed: zod_1.z.array(monthsIndexedSchema),
});
// Low-level schedule schema with custom validation
const lowLevelScheduleBase = zod_1.z.object({
    span: spanSchema,
    span_value: zod_1.z.number().int().positive(),
    habit_schedule: zod_1.z.number().int().positive().nullable(),
    habit_repeat_count: zod_1.z.number().int().positive().nullable(),
    program: zod_1.z.array(programSchema).min(1),
});
const lowLevelScheduleSchema = lowLevelScheduleBase.refine((data) => {
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
}, {
    message: 'habit_schedule must be calculated from habit_repeat_count × span × span_value (converted to days)',
});
// Main habit schema
exports.habitSchema = zod_1.z.object({
    name: zod_1.z.string().min(1),
    goal: zod_1.z.string().min(1),
    category: zod_1.z.string().min(1),
    description: zod_1.z.string().min(1),
    difficulty: difficultySchema,
    high_level_schedule: highLevelScheduleSchema,
    low_level_schedule: lowLevelScheduleSchema,
});
//# sourceMappingURL=habitSchema.js.map