import { z } from 'zod';

// Time format validation (HH:MM)
const timeFormatRegex = /^([0-1][0-9]|2[0-3]):[0-5][0-9]$/;
const timeSchema = z.string().regex(timeFormatRegex).nullable();

// Date format validation (YYYY-MM-DD)
const dateFormatRegex = /^\d{4}-\d{2}-\d{2}$/;
const dateSchema = z.string().regex(dateFormatRegex).nullable();

// Offset unit enum
const offsetUnitSchema = z.enum(['days', 'weeks', 'months']);

// Reminder offset schema
const reminderOffsetSchema = z.object({
  unit: offsetUnitSchema,
  value: z.number().int().positive(),
});

// Task reminder schema (only valid for steps with dates)
const taskReminderSchema = z.object({
  offset: reminderOffsetSchema,
  time: timeSchema,
  message: z.string().nullable(),
});

// Task step schema with custom validation
const taskStepSchema = z
  .object({
    index: z.number().int().positive(),
    title: z.string().min(1),
    description: z.string().nullable(),
    date: dateSchema,
    time: timeSchema,
    reminders: z.array(taskReminderSchema),
  })
  .refine(
    (data) => {
      // Reminders are only valid for steps with dates
      if (data.reminders.length > 0 && data.date === null) {
        return false;
      }
      return true;
    },
    {
      message: 'Reminders can only be set for steps that have a date',
      path: ['reminders'],
    }
  )
  .refine(
    (data) => {
      // Time should only be set if date is set
      if (data.time !== null && data.date === null) {
        return false;
      }
      return true;
    },
    {
      message: 'Time can only be set for steps that have a date',
      path: ['time'],
    }
  );

// Task schedule schema
const taskScheduleSchema = z.object({
  steps: z.array(taskStepSchema).min(1),
});

// Main task schema
export const taskSchema = z.object({
  name: z.string().min(1),
  goal: z.string().min(1),
  category: z.string().min(1),
  description: z.string().min(1),
  task_schedule: taskScheduleSchema,
});

// Type export for TypeScript
export type Task = z.infer<typeof taskSchema>;
export type TaskSchedule = z.infer<typeof taskScheduleSchema>;
export type TaskStep = z.infer<typeof taskStepSchema>;
export type TaskReminder = z.infer<typeof taskReminderSchema>;

