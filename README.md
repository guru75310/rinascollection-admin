# Rina's Collection Admin

Firebase-backed Flutter Web admin portal for managing products, images,
publishing, and customer orders.

The `functions` directory contains the server-side `placeOrder` callable. It
atomically validates prices and size stock, decrements inventory, creates the
order, and queues the confirmation email.

## Development

```powershell
flutter pub get
flutter analyze
flutter test
flutter build web --release
```

## Email notifications

Order creation and status changes queue documents in the Firestore `mail`
collection. Install the Firebase Trigger Email extension for the
`rinascollection` project and configure it to watch `mail`, using SendGrid SMTP
credentials. The SMTP credentials must stay in Firebase Extension configuration
and must not be committed to this repository.

## Deploying the order function

```powershell
npm.cmd install --prefix functions
firebase.cmd deploy --only functions,firestore:rules
```

The Firebase project must have billing enabled and the Cloud Build service
account must be allowed to build and deploy Cloud Functions.
