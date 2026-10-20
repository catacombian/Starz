# Planner iOS app

Personal, lightweight planner for a single user (me). Native iOS app: SwiftUI + SwiftData, iOS 26+.

## Screens
1. Today: list of today's tasks with checkboxes (completed = filled white circle with checkmark, strikethrough text).
2. Add/Edit Task: bottom sheet. Title required; description and time optional.
3. Month calendar: navigate months and tap any past or future day to see its task list.

## Rules
- Maximum 20 tasks (decide: per day or in total).
- If a task has a time, schedule two local notifications: 1 hour before and 10 minutes before.
  Skip any that are already in the past. Cancel/reschedule on edit, delete, or completion.
- Calendar dots: no tasks = no dot; some tasks open = purple dot; all tasks done = mint dot.

## Design
- Dark, minimal, native iOS glass effect (Liquid Glass) on floating elements only: top buttons, add sheet, New task button.
- Black background with a soft purple glow at the top; task list in dark gray cards.
- Accent: purple (#7C4DFF). Completed day dots: mint (#6EE7B7).
- System font (SF Pro), large rounded corners, touch targets at least 44pt.
- Reference mockups are in the design/ folder.

## Working style
- Build step by step: data model, Today, Add Task, notifications, calendar, polish.
- Keep the code simple and readable. Explain what you changed after each step.
