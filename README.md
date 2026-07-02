# AI-Powered Personal Finance Dashboard

AI-Powered Personal Finance Dashboard is a high-performance, responsive Flutter application for personal budgeting, transaction tracking, and insight-driven financial oversight. Built with Flutter and Riverpod, the app combines reactive UI state, local persistence, chart-based analytics, and configurable currency workflows to deliver a polished finance experience across dashboard, chat, and settings surfaces.

## Key Architectural Features

### State Management & Architecture
The application is structured around Riverpod-backed `Notifier` and `StateNotifier`-style state flows that keep the UI reactive without excessive widget coupling. Transaction lists, budget limits, currency preferences, and dashboard calculations are all driven from centralized providers, allowing screens to update immediately when local state changes.

### Local Persistence Layer
Persistent storage is implemented with `shared_preferences`, using JSON serialization to retain app data between launches. Transaction records, budget caps, category budgets, and preference values are serialized and hydrated locally so the dashboard remains usable even after app restarts or offline sessions.

### Dynamic Contextual Analytics Engine
The dashboard performs contextual financial analysis directly from the stored expenditure arrays. It calculates highest-spending categories, total usage ratios, breakdown percentages, and budget-versus-spend comparisons on the fly, ensuring that charts and insights always reflect the most recent transaction state.

### Internationalization & Customization
The Settings module supports live currency switching across major display tokens such as ₹, $, and € while dynamically recalculating monthly caps and category limits. Budget thresholds can be modified from the same interface, and the UI updates immediately to keep all displayed monetary values aligned with the selected currency context.

### Data Portability
The app includes built-in structured reporting through `_exportToCSV()`, enabling transaction data to be exported into a portable CSV format. This makes it easier to share records, archive financial activity, or move data into external spreadsheet and reporting tools.

## Project File Map

```text
my_finance/
├── lib/
│   └── main.dart
├── pubspec.yaml
├── README.md
├── analysis_options.yaml
├── android/
├── ios/
├── web/
├── windows/
├── macos/
├── linux/
└── test/
	 └── widget_test.dart
```

## Getting Started

1. Fetch dependencies:

	```bash
	flutter pub get
	```

2. Launch the application:

	```bash
	flutter run
	```

For development workflows that use Gemini-powered features, ensure your `.env` file is present at the project root and includes the expected API configuration before running the app.
