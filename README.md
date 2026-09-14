# Rina's Collection Admin

Firebase-backed Flutter Web admin portal for managing products, images,
publishing, and customer orders.

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
