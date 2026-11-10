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
- Calendar view and TodayView must use the shared EventRow. Long-press action is ‘Done’ for unticked items and ‘Undone’ for ticked ones.

## Design
- Dark, minimal, native iOS glass effect (Liquid Glass) on floating elements only: top buttons, add sheet, New task button.
- Black background with a soft purple glow at the top; task list in dark gray cards.
- Accent: purple (#7C4DFF). Completed day dots: mint (#6EE7B7).
- System font (SF Pro), large rounded corners, touch targets at least 44pt.
- Reference mockups are in the design/ folder.

## Widget
Home screen widget (small and medium) showing today's open tasks. Target `PlannerWidgetExtensionExtension`, code in `PlannerWidgetExtension/`. The `PlannerWidget/` folders are old copies and are not compiled.

- Shared data: the app and widget use one SwiftData store in the App Group `group.com.manhutava.Starz`, opened with `SharedStore.makeContainer()`. `PlannerTask.swift`, `Series.swift` and `Reminders.swift` are compiled into both targets.
- Writing: every change must end in `ModelContext.commit()`, which saves first and then reloads the widget. Use `addTask`, `updateTask`, `deleteTask`, `deleteSeries`, `makeRegular` or `toggleDone`, which already call it. Don't rely on autosave: the widget reads from disk, so unsaved changes don't reach it. New actions (e.g. reordering) must call `commit()` too.
- Reading: the widget opens a new container and context on every load with `SharedStore.withFreshContext`, so there is no stale cache. The container must outlive its context, or the app crashes.
- What it lists: `PlannerTask.openTasks(on:in:)`, today's tasks that aren't done, timed ones first in time order. It shows up to 3 on small and 5 on medium. Completed tasks disappear from the widget but stay crossed out in the app.
- Midnight: the timeline has two entries, now and the next midnight (already holding the next day's tasks), with policy `.after(midnight)`.
- Reload kind: `SharedStore.widgetKind` (`"PlannerWidgetExtension"`). A wrong kind silently does nothing.
- App lifecycle: going to the background calls `commit()` once more as a safety net.
- Check-off: tapping a row's star runs `CompleteTaskIntent` in the widget process and writes to the shared store. It sets the task done rather than toggling it, so a double tap can't undo it. The app has no extra refresh code; its `@Query` picked up writes from a second container in tests.
- Moving dates: the date field appears only when editing, and not for copies of a regular event, because `topUp` would recreate the moved copy on its original day.

## Working style
- Build step by step: data model, Today, Add Task, notifications, calendar, polish.
- Keep the code simple and readable. Explain what you changed after each step.

## graphify

This project has a knowledge graph at graphify-out/ with god nodes, community structure, and cross-file relationships.

Rules:
- When graphify-out/graph.json exists, run `graphify query "<question>"` before your first grep, search or source-file read for a codebase question, and put this rule in every subagent prompt that explores code. Read raw files only for lines the graph or an earlier read already located. Use `graphify path "<A>" "<B>"` for relationships and `graphify explain "<concept>"` for focused concepts. These return a scoped subgraph, usually much smaller than GRAPH_REPORT.md or raw grep output.
- If graphify-out/wiki/index.md exists, use it for broad navigation instead of raw source browsing.
- Read graphify-out/GRAPH_REPORT.md only for broad architecture review or when query/path/explain do not surface enough context.
- After modifying code, run `graphify update .` to keep the graph current (AST-only, no API cost).
- A committed graphify-out/graph.json is rewritten whole on every build, so a large diff to it in a pull request is expected. Do not flag it as churn or suggest skipping the graph rebuild or its hooks.
