# Admin App (Flutter)

Petite application Android qui affiche la page :
https://script.google.com/macros/s/AKfycbyN_k134kkvoqfq4h-oooFuz3zensDZtCIbkPrVNLDIJ73xvZghfLnu_X1jAYb985HkEg/exec?admin=1

## Récupérer l'APK
À chaque push, GitHub Actions compile l'APK : onglet **Actions** → dernier run
**Build APK** → artefact **app-release-apk**.

## Compiler en local
```bash
flutter create --platforms=android --org com.admin --project-name admin_app .
# ajouter <uses-permission android:name="android.permission.INTERNET"/>
# dans android/app/src/main/AndroidManifest.xml (avant <application>)
flutter build apk --release
```
L'APK se trouve dans `build/app/outputs/flutter-apk/app-release.apk`.
