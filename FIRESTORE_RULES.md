# Firestore rules for `reception` collection (example)

Below is an example of Firestore security rules to allow authenticated users to create messages in `reception`, while restricting read/update/delete to admin users only. Adjust the `isAdmin` check to match how you identify admins (custom claims or user document field).

```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    function isAdmin() {
      // Example: check a custom claim. Use whichever method you prefer.
      return request.auth != null && request.auth.token.admin == true;
      // Or, if you store roles in users collection:
      // return request.auth != null && get(/databases/$(database)/documents/users/$(request.auth.uid)).data.role == 'admin';
    }

    match /reception/{docId} {
      // Anyone authenticated can create a reception message
      allow create: if request.auth != null;

      // Only admins can read, update or delete reception messages
      allow read, update, delete: if isAdmin();
    }

    // Keep rest of your rules below
  }
}
```

Notes:
- If you want unauthenticated users to be able to send messages (e.g., contact form), change `allow create: if request.auth != null;` to `allow create: if true;` but be cautious about spam.
- Use Cloud Functions to sanitize/validate input if needed.
- Test your rules in the Firebase console simulator before deploying.
