# Famotive

A Flutter mobile application designed to help families stay organized, connected, and motivated.

## Getting Started

### Prerequisites

Make sure you have the following installed:

- [Flutter](https://docs.flutter.dev/get-started/install)
- Dart (included with Flutter)
- Android Studio or Xcode (for Compiling Mobile App)
- VSCode
- Git

### Setup

Clone the repository:

```bash
git clone <repository-url>
cd <repository>
```

Install dependencies:

```bash
flutter pub get
```

Run the application:

```bash
flutter run
```

## Project Structure

```text
Famotive/
│
├── android/
├── ios/
│
├── assets/
│   ├── images/
│   ├── icons/
│   └── fonts/
│
├── lib/
│   │
│   ├── main.dart
│   │
│   ├── app/
│   │   ├── app.dart
│   │   ├── routes.dart
│   │   └── theme.dart
│   │
│   ├── core/
│   │   ├── constants/
│   │   │   └── app_constants.dart
│   │   │
│   │   ├── models/
│   │   │   ├── user.dart
│   │   │   ├── household.dart
│   │   │   ├── task.dart
│   │   │   └── reward.dart
│   │   │
│   │   ├── services/
│   │   │   ├── api_service.dart
│   │   │   ├── auth_service.dart
│   │   │   └── database_service.dart
│   │   │
│   │   └── utils/
│   │       └── validators.dart
│   │
│   ├── features/
│   │   │
│   │   ├── auth/
│   │   │   ├── screens/
│   │   │   │   ├── login_screen.dart
│   │   │   │   └── register_screen.dart
│   │   │   └── widgets/
│   │   │
│   │   ├── household/
│   │   │   ├── screens/
│   │   │   ├── widgets/
│   │   │   └── services/
│   │   │
│   │   ├── tasks/
│   │   │   ├── screens/
│   │   │   │   ├── task_list_screen.dart
│   │   │   │   ├── task_detail_screen.dart
│   │   │   │   └── create_task_screen.dart
│   │   │   ├── widgets/
│   │   │   └── services/
│   │   │
│   │   ├── rewards/
│   │   │   ├── screens/
│   │   │   ├── widgets/
│   │   │   └── services/
│   │   │
│   │   └── profile/
│   │       ├── screens/
│   │       └── widgets/
│   │
│   └── shared/
│       ├── widgets/
│       │   ├── app_button.dart
│       │   ├── app_card.dart
│       │   └── loading_indicator.dart
│       │
│       └── layouts/
│           └── app_scaffold.dart
│
├── test/
│   ├── core/
│   └── features/
│
├── pubspec.yaml
├── README.md
└── .gitignore
```

## Development

Create a feature branch from `dev`:

```bash
git switch dev
git pull
git switch -c feature/<feature-name>
```

After completing your work, commit and push your branch:

```bash
git add .
git commit -m "Add <feature>"
git push -u origin feature/<feature-name>
```

Then open a pull request into `dev`.

## Tech Stack

- **Flutter**
- **Dart**
- **Firebase** — Authentication and backend services

## What am I looking at?

There is an onboarding guide located in [Documents/Flutter.md](Documents/Flutter.md)

## Team

Famotive is a team project developed as part of a Full Sail University course.
