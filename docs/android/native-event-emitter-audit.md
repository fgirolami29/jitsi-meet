# Android NativeEventEmitter audit

## Contesto

Il build Android `labRelease` usa React Native 0.66.4 e incorpora il
bundle JavaScript direttamente nell'APK.

Durante l'avvio venivano prodotti quattro warning:

- modulo privo di `addListener`;
- modulo privo di `removeListeners`;
- modulo privo di `addListener`;
- modulo privo di `removeListeners`.

## Diagnosi eseguita

La diagnosi è stata effettuata in due passaggi:

1. verifica che il bundle generato dal modulo SDK fosse realmente quello
   contenuto nell'APK;
2. instrumentazione temporanea dei call-site che costruiscono
   `NativeEventEmitter`.

Il bundle generato e il bundle estratto dall'APK sono risultati identici.

## Risultato comprovato

Call-site caricati:

- `react-native-background-timer/index.js`;
- `react-native-performance/src/index.ts`;
- `react-native-reanimated/src/ReanimatedEventEmitter.js`.

Moduli che generano effettivamente i warning:

- `react-native-background-timer@2.4.1`;
- `react-native-reanimated@1.13.3`.

`react-native-performance@2.1.0` viene caricato, ma non genera warning e
non deve essere modificato.

## Causa

React Native 0.66 verifica che ogni modulo nativo passato a
`NativeEventEmitter` esponga i metodi:

- `addListener`;
- `removeListeners`.

I moduli Android delle due dipendenze responsabili non implementano
questi metodi.

## Decisione tecnica

La correzione viene applicata tramite `patch-package`, senza modificare
i call-site JavaScript e senza silenziare globalmente i warning di React
Native.

Nei due moduli Android vengono aggiunti metodi bridge senza contabilità
interna, perché le librerie continuano a gestire gli eventi con il loro
comportamento esistente.

Questa scelta:

- soddisfa il contratto di `NativeEventEmitter`;
- non cambia la logica degli eventi;
- non modifica React Native globalmente;
- resta riproducibile dopo ogni `npm install` grazie al `postinstall`;
- limita la modifica alle sole dipendenze comprovate.
