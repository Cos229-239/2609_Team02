CLI Prerequisites Before Starting a New Project

Universal (everyone, every platform)
These are non-negotiable because commands operate on the current folder.

Verify you’re in the right place (in the terminal window CLI aka Command Line Interface)

  pwd
  ls
  git --version

  Ok now they you know that you have git installed and you can see you are in the project folder...

  
⸻




**** Web app (Node / React / Next / Vite)
  Assume you'll do at least one of these.

First run this to see if you have the required files
	node -v
	npm -v
	npx -v
If it returns nothing it means you need to install Node.js LTS 
	•	Go to nodejs.org
	•	Download LTS
	•	Run the .pkg installer

Now that you verified you have those installed:
	
  Create a project
	.
    For Next.js:
      npx create-next-app@latest my-app
  .
    For Vite:
      npm create vite@latest my-app
  .
    Install dependencies
      npm install
  .
    Run the dev server
      npm run dev

Why: These tools generate the folder structure, install libraries, and start the dev process. IDE buttons are wrappers; CI uses the CLI.


⸻


**** Android Kotlin app (Android Studio + Gradle)
  Even if Android Studio makes the project, Gradle is the build engine.
  
  Verify Gradle wrapper exists (project root)
    ls
      # you should see: gradlew, settings.gradle(.kts), build.gradle(.kts)
  
  Build from CLI
    ./gradlew build
  
  Run tests from CLI
    ./gradlew test

  Optional (common): list tasks / diagnose
    ./gradlew tasks

Why: This proves the project builds without the IDE (same requirement as CI). When Studio “Builds”, it’s driving Gradle.


⸻


**** iOS app (Xcode + xcodebuild)
  Xcode can create projects, but CI and automation use xcodebuild.
  .
    Verify Xcode CLI tools
      xcodebuild -version
  .
    List/build (project-specific example)
      From the iOS project folder:
        xcodebuild -list
  .
    In Xcode / iOS, a scheme is simply:
    A named build/run configuration for an app or target.
  .
    It answers:
	    •	What am I building?
	    •	How am I building it?
	    •	What am I running or testing?
  .
    Most projects have at least one scheme with the same name as the app.
  .  
    Then (once you know the scheme):
      xcodebuild -scheme "YourScheme" build
  .
    Run tests
      xcodebuild -scheme "YourScheme" test

  Why: iOS builds must be automatable. xcodebuild is the canonical build interface; Xcode is the GUI front-end.
