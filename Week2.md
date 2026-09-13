Objectives for today:
- Setup our Firebase account
- Add Firebase to the project

-- Configure Accounts
-Parent Account
--- Household
------  Child Account
        Tasks

SQL Lite in the app, this contains all household tasks. Pulled from firebase so when device is online it syncs.

One database per household
Household will have a password to access and update shared by the entire family. (for now text) - do a qr code secret key later

------------------
Firebase Authentication: Essential for securing family accounts. It lets parents and children sign in safely, allowing you to manage roles (e.g., distinguishing who is a parent authorized to assign chores).

Cloud Firestore: A flexible NoSQL database ideal for storing chore lists, task statuses, and rewards. Its real-time listeners will instantly update a child's device when a parent assigns a chore.

Firebase Cloud Messaging (FCM): Great for keeping families aligned. You can send push notifications to notify children of new tasks, or alert parents the moment a chore is marked complete.
------------------
