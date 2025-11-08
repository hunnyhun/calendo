"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.taskSchema = void 0;
const zod_1 = require("zod");
// Time format validation (HH:MM)
const timeFormatRegex = /^([0-1][0-9]|2[0-3]):[0-5][0-9]$/;
const timeSchema = zod_1.z.string().regex(timeFormatRegex).nullable();
// Date format validation (YYYY-MM-DD)
const dateFormatRegex = /^\d{4}-\d{2}-\d{2}$/;
const dateSchema = zod_1.z.string().regex(dateFormatRegex).nullable();
// Offset unit enum
const offsetUnitSchema = zod_1.z.enum(['days', 'weeks', 'months']);
// Reminder offset schema
const reminderOffsetSchema = zod_1.z.object({
    unit: offsetUnitSchema,
    value: zod_1.z.number().int().positive(),
});
// Task reminder schema (only valid for steps with dates)
const taskReminderSchema = zod_1.z.object({
    offset: reminderOffsetSchema,
    time: timeSchema,
    message: zod_1.z.string().nullable(),
});
// Task step schema with custom validation
const taskStepSchema = zod_1.z
    .object({
    index: zod_1.z.number().int().positive(),
    title: zod_1.z.string().min(1),
    description: zod_1.z.string().nullable(),
    date: dateSchema,
    time: timeSchema,
    reminders: zod_1.z.array(taskReminderSchema),
})
    .refine((data) => {
    // Reminders are only valid for steps with dates
    if (data.reminders.length > 0 && data.date === null) {
        return false;
    }
    return true;
}, {
    message: 'Reminders can only be set for steps that have a date',
    path: ['reminders'],
})
    .refine((data) => {
    // Time should only be set if date is set
    if (data.time !== null && data.date === null) {
        return false;
    }
    return true;
}, {
    message: 'Time can only be set for steps that have a date',
    path: ['time'],
});
// Task schedule schema
const taskScheduleSchema = zod_1.z.object({
    steps: zod_1.z.array(taskStepSchema).min(1),
});
// Main task schema
exports.taskSchema = zod_1.z.object({
    name: zod_1.z.string().min(1),
    goal: zod_1.z.string().min(1),
    category: zod_1.z.string().min(1),
    description: zod_1.z.string().min(1),
    task_schedule: taskScheduleSchema,
});
//# sourceMappingURL=taskSchema.js.map