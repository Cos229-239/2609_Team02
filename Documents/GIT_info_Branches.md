Git Branches — How We Work in This Course

This document explains how Git branches are used in this course, where you are expected to push, and why this structure exists.
Following this workflow is part of your professional responsibility.

⸻

GitHub Branches as a Library

Think of your project as a library, and each Git branch as a different place where work lives.
This structure keeps work safe, organized, and collaborative.

⸻
What is it?

🟢 MAIN — The Museum Shelf

This is the clean, curated shelf where approved work is published.
	•	Represents the official project state
	•	This is what someone would look at to evaluate the project as a whole
	•	Work is pushed here only by the Build Master
	•	Not everyone writes here, and not all the time

Important:
Pushing to main is a role-based (The Build Master)responsibility, not a default action.

Why?

🟢 main — Where the Build Master Publishes

Where you push:
	•	Only the Build Master pushes to main

Why:
	•	main must stay:
	•	stable
	•	buildable
	•	review-ready
	•	Limiting access prevents accidental breakage and confusion

Pushing to main is a responsibility, not a privilege.

⸻

What is it?

🟡 DEV — The Group Table

This is where the team brings their work together to see how it functions as one project.
	•	All team contributions are integrated here first
	•	This is where:
	•	features come together
	•	conflicts are discovered
	•	bugs are identified
	•	Team members merge their work into dev
	•	dev is the primary branch used for:
	•	testing
	•	build reviews
	•	grading checks

You generally do not write directly in dev.
You merge (UP) into it.

Why?

🟡 dev — Where the Team Integrates

Where you push:
	•	Into dev, usually via a merge, once your work is ready to be tested with others

Why:
	•	dev is where:
	•	everyone’s work comes together
	•	integration problems are found
	•	**the team project** is evaluated during build reviews

Rule:
If your work is not in dev, it is not part of **the team project** yet.

⸻

What is it?

🔵 Personal Branch (e.g., alex-feature, jamie-ui) — Your Desk

  This is your personal workspace. Your experiments. Your drafts.
  	•	You write code here
  	•	You test ideas here
  	•	You can break things safely here
  	•	No one else touches this branch
  
  This branch exists so you can work without risking the shared project state.
  
  ⸻
  
  Where You Push (and Why)
  
  In this course, where you push your code matters.
  Each branch has a purpose. Pushing to the wrong place causes real problems.
  
⸻

Why?

🔵 Personal Branch — Where You Work

  Where you push:
  	•	Your personal branch
  
  Why:
  	•	This is where you are allowed to:
  	•	experiment
  	•	make mistakes
  	•	work without breaking the team build
  	•	No one else is affected by your changes here
  
  Rule:
  You always start by pushing to your own branch.


⸻

What Is the Build Master?

  The Build Master is a team role responsible for:
  	•	Reviewing what’s currently in dev
  	•	Making sure the project builds and runs
  	•	Resolving last-minute conflicts
  	•	Pushing approved work to main

  This mirrors real-world roles such as:
  	•	release manager
  	•	integration lead
  	•	build engineer

Not everyone does this job — and that’s intentional.

⸻

Correct Workflow (Memorize This)
	1.	Work at your desk isolated, aka solo (your personal branch)
	2.	Merge into the team (dev - shared workspace)
	3.	Build Master publishes to the class (Build Master pushes to main)

Skipping steps creates risk for the entire team.

⸻

Rules You Are Expected to Follow
	•	Do not work directly in main
	•	Do not bypass dev
	•	Do not push unfinished work to shared branches
	•	Do not assume someone else will fix your mistakes

If your work:
	•	is not merged into dev, it is not teamwork
	•	exists only on your computer; it is not protected
	•	is pushed to the wrong branch, it may be reverted

⸻

Why This Structure Exists

This workflow:
	•	protects everyone’s work
	•	prevents accidental damage
	•	makes collaboration visible
	•	supports fair grading
	•	mirrors professional development pipelines

Following it is part of your professional responsibility in this course.

⸻

Note:
This branching structure exists to protect the project and ensure consistent collaboration. Failure to follow it may result in lost work or grading issues.
