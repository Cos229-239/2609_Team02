Cloning the Repo & Creating Your Personal Branch (GitHub Desktop)

This guide walks you through two parts:
	1.	Cloning the team repository
	2.	Creating your personal branch

You are not required to use the terminal for this course.

Required Tool
	•	GitHub Desktop
	•	You must be logged in with your GitHub account

If you are not logged in, stop and fix that first.



⸻ PART 1 ⸻ 

************** Setup **************

Cloning creates a local copy of the team repository on your computer.

Accepting the Repository Invite Via email (Required Before Cloning)
  Before you can clone the team repository, you must accept the GitHub invitation.
  This happens outside of GitHub Desktop.

You should check your email only after the instructor has notified the class that:
	•	Team repositories have been created
	•	GitHub invites have been sent
  •	If you check too early, there may be nothing to accept yet.

You will receive an email from GitHub with a subject similar to:
  You’ve been invited to collaborate on a repository

  Inside the email, there will be a link that says something like:
	  •	Accept invitation
	  •	View invitation
	  •	Join repository

  Click the link.

  What Accepting the Invite Does

  Accepting the invite:
	  •	Adds the repository to your GitHub account
	  •	Grants you access to the team repo
	  •	Allows GitHub Desktop to see and clone the repo

  Until you accept the invite:
	  •	The repo will not appear in GitHub Desktop
	  •	You cannot clone it
	  •	Nothing is “broken” — you just don’t have access yet

  How to Verify You Accepted It
    After clicking the invite link:
	    1.	Log into github.com
	    2.	Go to your repositories
	    3.	Confirm the team repo appears in your list

  Only after this should you open GitHub Desktop to clone.

Now you are ready to clone. 

************** Step 1B: Cloning **************

Note:
GitHub Desktop should prompt you to choose a Local Destination when you clone.

Steps (GitHub Desktop)
	1.	Open GitHub Desktop
	2.	Go to File → Clone Repository
	3.	Select the GitHub.com tab
	4.	Choose the team repository
	5.	Click Clone

That’s it.



⸻ PART 2 ⸻ 



************** Verify You’re on the Correct Branch **************

After cloning:
	•	Look at the Current Branch dropdown at the top
	•	Make sure you are on dev
	•	If not, select dev

You should not be working in main.


************** Create Your Personal Branch **************

Your personal branch is where you do your work.

Steps (GitHub Desktop)
	1.	In GitHub Desktop, click Current Branch
	2.	Click New Branch
	3.	Name your branch using this format:
          "yourname-personal" is the default
          "yourname-feature" is done if you are doing it feature-based.
	4.	Base the branch on dev
	5.	Click Create Branch

You are now working on your own personal copy (isolated).


************** Publish Your Branch **************

Your branch exists locally until you publish it.
	1.	Click Publish branch
	2.	GitHub Desktop will push it to GitHub

Now your branch exists:
	•	locally and
	•	on GitHub

Done!

This protects your work.

What You Should See before you start coding

Confirm:
	•	GitHub Desktop shows:
	•	Your GitHub username
	•	Your personal branch name
	•	The branch is not main
	•	The branch is not dev

If all of that is true, you’re ready to work.





⸻ Notes and other helpful info ⸻ 



Do I Ever Need the Terminal?

No.
	•	You are not required to use the terminal (although you might use it if you get in a jam)
	•	All required actions can be done in GitHub Desktop
	•	Using the terminal incorrectly can damage the repo

If you already know Git CLI, you may use it at your own risk.

Common Mistakes to Avoid
	•	Working directly in main
	•	Working directly in dev
	•	Forgetting to publish your branch
	•	Creating a branch off main instead of dev

If you’re unsure — stop and ask a teammate before pushing.

Why This Matters

This process:
	•	protects the shared project
	•	prevents lost work
	•	makes collaboration visible
	•	allows fair grading

Following it is part of your professional responsibility.
