# fake_cloud_firestore 4.3.0 (patched)

Copy of https://github.com/atn832/fake_cloud_firestore (BSD license, see
LICENSE) at version 4.3.0, with one change: `MockFieldValueFactoryPlatform`
and `MockFieldValuePlatform` no longer mix in `MockPlatformInterfaceMixin`.

That mixin makes `FieldValueFactoryPlatform.instance = ...` throw
"`MockPlatformInterfaceMixin` is not intended for use in release builds",
so the stock package can't run in a release web build. The QA build at
famotive.org/qa/walkthrough (lib/qa/) runs the whole app on this in-memory
Firestore, so it needs it to work in release.

Search for "Famotive patch" to see the edits. When upgrading, re-apply them.
