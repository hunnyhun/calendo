# Habit Mapping Functions Explanation

This document explains how the three mapping functions (`dailyHabitMapping`, `weeklyHabitMapping`, `monthlyHabitMapping`) convert habit JSON data into calendar dates for display in habit cards.

## Overview

All three functions follow the same pattern:
1. **Extract** indexed items from the habit JSON
2. **Calculate** actual calendar dates based on the index and start date
3. **Extract** common habit info (name, goal, category, etc.)
4. **Extract** schedule-specific data (steps, reminders, titles)
5. **Return** a dictionary mapping dates to habit card data

---

## 1. `dailyHabitMapping` Function

### Purpose
Maps habits that have `days_indexed` items to specific calendar dates. Each day index represents a day offset from the habit start date.

### How It Works

**Input Example:**
```json
{
  "name": "Morning Meditation",
  "goal": "Build daily meditation practice",
  "category": "mindfulness",
  "description": "10 minutes of meditation",
  "difficulty": "beginner",
  "low_level_schedule": {
    "span": "day",
    "span_value": 7,
    "habit_schedule": 30,
    "span_interval": null,
    "program": [{
      "days_indexed": [
        {
          "index": 0,
          "title": "First Day Meditation",
          "content": [
            {"step": "Sit comfortably for 10 minutes", "clock": "07:00"}
          ],
          "reminders": [
            {"time": "06:30", "message": "Time for morning meditation"}
          ]
        },
        {
          "index": 2,
          "title": "Day 3 Practice",
          "content": [
            {"step": "Focus on breathing", "clock": "07:00"}
          ],
          "reminders": [
            {"time": "06:30", "message": "Don't forget your meditation"}
          ]
        }
      ]
    }]
  }
}
```

**Process:**
1. Start date: `2024-01-15` (when user starts the habit)
2. For `index: 0`: 
   - Date = startDate + 0 days = `2024-01-15`
   - Creates habit card for January 15, 2024
3. For `index: 2`:
   - Date = startDate + 2 days = `2024-01-17`
   - Creates habit card for January 17, 2024

**Output:**
```swift
[
  2024-01-15: HabitCardData(
    name: "Morning Meditation",
    goal: "Build daily meditation practice",
    category: "mindfulness",
    title: "First Day Meditation",
    steps: [
      HabitStepDisplay(step: "Sit comfortably for 10 minutes", clock: "07:00")
    ],
    reminders: [
      HabitReminderDisplay(time: "06:30", message: "Time for morning meditation")
    ]
  ),
  2024-01-17: HabitCardData(
    name: "Morning Meditation",
    goal: "Build daily meditation practice",
    category: "mindfulness",
    title: "Day 3 Practice",
    steps: [
      HabitStepDisplay(step: "Focus on breathing", clock: "07:00")
    ],
    reminders: [...]
  )
]
```

**Key Points:**
- `index: 0` = first day (startDate)
- `index: 1` = second day (startDate + 1 day)
- Each day can have multiple steps with clock times
- Steps are displayed on the habit card with their scheduled times

---

## 2. `weeklyHabitMapping` Function

### Purpose
Maps habits that have `weeks_indexed` items to specific days within specific weeks. The week index determines which week, and the day name determines which day of that week.

### How It Works

**Input Example:**
```json
{
  "name": "Weekly Workout",
  "goal": "Exercise 3 times per week",
  "category": "physical",
  "low_level_schedule": {
    "span": "week",
    "span_value": 4,
    "habit_schedule": 12,
    "span_interval": null,
    "program": [{
      "weeks_indexed": [
        {
          "index": 0,
          "title": "Week 1: Foundation",
          "content": [
            {"step": "30 min cardio", "day": "Monday"},
            {"step": "Upper body strength", "day": "Wednesday"},
            {"step": "Yoga stretch", "day": "Friday"}
          ],
          "reminders": [
            {"time": "08:00", "message": "Workout time!"}
          ]
        },
        {
          "index": 1,
          "title": "Week 2: Building",
          "content": [
            {"step": "45 min cardio", "day": "Monday"},
            {"step": "Full body strength", "day": "Wednesday"}
          ],
          "reminders": [...]
        }
      ]
    }]
  }
}
```

**Process:**
1. Start date: `2024-01-15` (Monday)
2. For `index: 0` (Week 1):
   - Week 1 starts: `2024-01-15`
   - Monday in Week 1: `2024-01-15` → "30 min cardio"
   - Wednesday in Week 1: `2024-01-17` → "Upper body strength"
   - Friday in Week 1: `2024-01-19` → "Yoga stretch"
3. For `index: 1` (Week 2):
   - Week 2 starts: `2024-01-22` (7 days after Week 1)
   - Monday in Week 2: `2024-01-22` → "45 min cardio"
   - Wednesday in Week 2: `2024-01-24` → "Full body strength"

**Output:**
```swift
[
  2024-01-15: HabitCardData( // Monday, Week 1
    name: "Weekly Workout",
    title: "Week 1: Foundation",
    steps: [
      HabitStepDisplay(step: "30 min cardio", day: "Monday")
    ]
  ),
  2024-01-17: HabitCardData( // Wednesday, Week 1
    name: "Weekly Workout",
    title: "Week 1: Foundation",
    steps: [
      HabitStepDisplay(step: "Upper body strength", day: "Wednesday")
    ]
  ),
  2024-01-19: HabitCardData( // Friday, Week 1
    name: "Weekly Workout",
    title: "Week 1: Foundation",
    steps: [
      HabitStepDisplay(step: "Yoga stretch", day: "Friday")
    ]
  ),
  2024-01-22: HabitCardData( // Monday, Week 2
    name: "Weekly Workout",
    title: "Week 2: Building",
    steps: [
      HabitStepDisplay(step: "45 min cardio", day: "Monday")
    ]
  ),
  // ... more dates
]
```

**Key Points:**
- `index: 0` = first week (starting from startDate)
- `index: 1` = second week (7 days after first week)
- Day names ("Monday", "Tuesday", etc.) are converted to actual calendar dates
- Multiple steps on the same day are grouped together
- Each week can have different activities

---

## 3. `monthlyHabitMapping` Function

### Purpose
Maps habits that have `months_indexed` items to specific days within specific months. The month index determines which month, and the day number determines which day of that month.

### How It Works

**Input Example:**
```json
{
  "name": "Monthly Review",
  "goal": "Reflect and plan each month",
  "category": "productivity",
  "low_level_schedule": {
    "span": "month",
    "span_value": 3,
    "habit_schedule": 12,
    "span_interval": null,
    "program": [{
      "months_indexed": [
        {
          "index": 0,
          "title": "First Month Review",
          "content": [
            {"step": "Review goals and achievements", "day": "1"},
            {"step": "Set new monthly objectives", "day": "end_of_month"}
          ],
          "reminders": [
            {"time": "09:00", "message": "Monthly review time"}
          ]
        },
        {
          "index": 1,
          "title": "Second Month Review",
          "content": [
            {"step": "Assess progress", "day": "1"},
            {"step": "Adjust strategy", "day": "15"}
          ],
          "reminders": [...]
        }
      ]
    }]
  }
}
```

**Process:**
1. Start date: `2024-01-15`
2. For `index: 0` (Month 1 = January 2024):
   - Day 1: `2024-01-01` → "Review goals and achievements"
   - End of month: `2024-01-31` → "Set new monthly objectives"
3. For `index: 1` (Month 2 = February 2024):
   - Day 1: `2024-02-01` → "Assess progress"
   - Day 15: `2024-02-15` → "Adjust strategy"

**Output:**
```swift
[
  2024-01-01: HabitCardData( // Day 1, Month 1
    name: "Monthly Review",
    title: "First Month Review",
    steps: [
      HabitStepDisplay(step: "Review goals and achievements", dayOfMonth: 1)
    ]
  ),
  2024-01-31: HabitCardData( // End of month, Month 1
    name: "Monthly Review",
    title: "First Month Review",
    steps: [
      HabitStepDisplay(step: "Set new monthly objectives", dayOfMonth: 31)
    ]
  ),
  2024-02-01: HabitCardData( // Day 1, Month 2
    name: "Monthly Review",
    title: "Second Month Review",
    steps: [
      HabitStepDisplay(step: "Assess progress", dayOfMonth: 1)
    ]
  ),
  2024-02-15: HabitCardData( // Day 15, Month 2
    name: "Monthly Review",
    title: "Second Month Review",
    steps: [
      HabitStepDisplay(step: "Adjust strategy", dayOfMonth: 15)
    ]
  )
]
```

**Key Points:**
- `index: 0` = first month (starting from startDate's month)
- `index: 1` = second month (1 month after first month)
- Day numbers: "1" to "28" (or "end_of_month" for last day)
- "end_of_month" automatically calculates the last day (28, 29, 30, or 31)
- Handles months with different lengths (February has 28/29 days)

---

## How Data Appears in Views

When the calendar view loads, it:

1. **Calls the appropriate mapping function** based on the habit's schedule type
2. **Gets a dictionary** of dates → HabitCardData
3. **For each date**, displays a habit card showing:
   - **Common Info**: Name, goal, category, description, difficulty
   - **Schedule-Specific Info**: 
     - Daily: Steps with clock times (e.g., "07:00")
     - Weekly: Steps with day names (e.g., "Monday")
     - Monthly: Steps with day numbers (e.g., "15th")
   - **Reminders**: Time and message

### Example Calendar View Display

**January 15, 2024:**
```
┌─────────────────────────────┐
│ 🌅 Morning Meditation       │
│ Build daily meditation      │
│                             │
│ First Day Meditation        │
│ • Sit comfortably (07:00)   │
│                             │
│ ⏰ Reminder: 06:30           │
└─────────────────────────────┘

┌─────────────────────────────┐
│ 💪 Weekly Workout            │
│ Exercise 3 times per week   │
│                             │
│ Week 1: Foundation          │
│ • 30 min cardio             │
│                             │
│ ⏰ Reminder: 08:00           │
└─────────────────────────────┘
```

---

## Schedule Constraints

All functions respect these constraints:

- **`span_interval`**: If set, limits how many times the habit repeats
  - Example: `span_interval: 4` means repeat 4 times max
  - If `null`, repeats indefinitely (or until `habit_schedule`)

- **`habit_schedule`**: Maximum total duration
  - Example: `habit_schedule: 30` means max 30 days/weeks/months

- **`span_value`**: Multiplier for the span
  - Example: `span: "week", span_value: 2` = every 2 weeks

These constraints ensure habits don't appear on dates beyond their intended duration.

---

## Summary

| Function | Input | Calculation | Output |
|----------|-------|-------------|--------|
| `dailyHabitMapping` | `days_indexed` with index | `startDate + index days` | Dates with daily steps and clock times |
| `weeklyHabitMapping` | `weeks_indexed` with index + day name | `startDate + (index * 7) days` + find day name | Dates with weekly steps and day names |
| `monthlyHabitMapping` | `months_indexed` with index + day number | `startDate + index months` + day of month | Dates with monthly steps and day numbers |

All functions return `[Date: HabitCardData]` which the calendar view uses to display habit cards on the appropriate dates.

