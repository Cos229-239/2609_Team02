Merging Your Work into dev (GitHub Desktop)

This guide explains how and when to merge your personal branch into the shared dev branch using GitHub Desktop.

This is a required workflow skill in this course.

⸻

What “Merging” Means

Merging means:

Taking work from your personal branch and integrating it into the shared team branch.

A merge is how your work becomes:
	•	visible to the team
	•	testable with other features
	•	eligible for grading as team work

If your work is not merged into dev, it is not part of the team project.

When You Merge

You merge when:
	•	your change works locally
	•	it is ready to be tested with others
	•	it will not break the build

For this first task, you will merge only your README name change.

⸻

Before You Merge (Required Check)

Before merging, confirm:
	•	You are on your personal branch
	•	Your change is:
	•	committed
	•	pushed to GitHub
	•	You are not on main

If any of those are not true, stop and fix them first.




⸻ Walkthrough ⸻  

How to Merge into dev (GitHub Desktop)

Step 1: Switching to dev
	1.	Open GitHub Desktop
	2.	Click Current Branch
	3.	Select dev

  NOTE: If you get a pop-up that asks you if you want to bring in the changes or stash them, stop here. You missed a step in Git_02 "Commit and Push" section.  
  Cancel and go back and follow they steps in that section. 


Once you have switched to DEV
You are now standing at the group table (metaphor).

Step 2: Merging Your Branch into dev
	1.	With dev selected, click Branch → Merge into Current Branch (its a menu item up top)
	2.	Choose your personal branch
	3.	Click Merge

GitHub Desktop will attempt the merge (this only STAGES it)

Step 3: Resolve Conflicts (If Any)
	•	If no conflicts appear → continue
	•	If a conflict appears:
	•	Follow GitHub Desktop’s instructions
	•	Ask for help if unsure
	•	Do not force a merge you don’t understand

Conflicts are normal. Mishandling them is not.

Step 4: Push dev (a push is the last setup OF merge)

After a successful merge:
	1.	Click Push origin (its button next to the branch selector)

Your change is now:
	•	in dev
	•	visible to the team
	•	part of the shared project state




⸻ Verify and Notes⸻ 

What You Should See (you can also check using the Github webpage)

After merging:
	•	GitHub Desktop shows:
	•	branch: dev
	•	a merge commit (if applicable)
	•	The README in dev now includes your name

At this point, your contribution is officially part of the team project.



⸻



Important Rules
	•	Do not merge into main
	•	Do not skip dev
	•	Do not delete your personal branch yet
	•	Always merge from your branch → into dev

⸻

Build Master Note
	•	The Build Master later reviews dev
	•	If stable, the Build Master pushes approved work to main
	•	Individual contributors do not push directly to main

⸻

Why This Matters

This process:
	•	proves collaboration
	•	prevents accidental breakage
	•	makes work visible for grading
	•	mirrors real-world team workflows

This is not busywork — it is how professional teams operate.

⸻

This First Merge Is Intentional

Merging a README change is:
	•	low risk
	•	easy to verify
	•	a safe way to learn the process

If something goes wrong here, it can be fixed quickly.

