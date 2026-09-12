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
│   │   ├── config/
│   │   │   └── app_config.dart
│   │   │
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
│   │   │       └── auth_text_field.dart
│   │   │
│   │   ├── household/
│   │   │   ├── screens/
│   │   │   │   ├── family_screen.dart
│   │   │   │   └── household_home_screen.dart
│   │   │   ├── services/
│   │   │   │   └── household_service.dart
│   │   │   └── widgets/
│   │   │       └── family_member_card.dart
│   │   │
│   │   ├── tasks/
│   │   │   ├── screens/
│   │   │   │   ├── task_list_screen.dart
│   │   │   │   ├── task_detail_screen.dart
│   │   │   │   ├── create_task_screen.dart
│   │   │   │   └── task_completion_screen.dart
│   │   │   ├── services/
│   │   │   │   └── task_service.dart
│   │   │   └── widgets/
│   │   │       └── task_tile.dart
│   │   │
│   │   ├── rewards/
│   │   │   ├── screens/
│   │   │   │   ├── progress_screen.dart
│   │   │   │   └── reward_choose_screen.dart
│   │   │   ├── services/
│   │   │   │   └── reward_service.dart
│   │   │   └── widgets/
│   │   │       └── reward_tile.dart
│   │   │
│   │   └── profile/
│   │       ├── screens/
│   │       │   └── profile_screen.dart
│   │       └── widgets/
│   │           └── profile_menu_tile.dart
│   │
│   └── shared/
│       ├── layouts/
│       │   └── main_tab_shell.dart
│       │
│       └── widgets/
│       │   ├── app_button.dart
│       │   ├── app_card.dart
│       │   └── loading_indicator.dart
│
├── test/
│   ├── app_smoke_test.dart
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

<table>
<tr>
<td width="160" align="center">

<img src="https://github.com/skidgfx.png" width="120" height="120" style="border-radius: 50%;">

</td>
<td>

# Nathan Pillman
### `SOFTWARE ENGINEER // SYSTEMS`

> **CALLSIGN:** @SKIDGFX  
> **STATUS:** `ONLINE`  
> **SPECIALIZATION:** FULL-STACK / C++ / DART  

</td>
</tr>
<tr>
<td width="160" align="center">

<img src="https://github.com/babyrhedd.png" width="120" height="120" style="border-radius: 50%;">

</td>
<td>

# Ashley Campbell
### `SOFTWARE ENGINEER // UI`

> **CALLSIGN:** @babyrhedd  
> **STATUS:** `ONLINE`  
> **SPECIALIZATION:** FRONT-END / C++  

</td>
</tr>
<tr>
<td width="160" align="center">

<img src="https://github.com/TKLoum.png" width="120" height="120" style="border-radius: 50%;">

</td>
<td>

# Tiffany Loum
### `SOFTWARE ENGINEER // QA`

> **CALLSIGN:** @TKLoum.  
> **STATUS:** `ONLINE`  
> **SPECIALIZATION:**  

</td>
</tr>
</table>

