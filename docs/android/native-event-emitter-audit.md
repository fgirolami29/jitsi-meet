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

## Risoluzione applicata

La correzione è stata resa persistente tramite:

- `patches/react-native-background-timer+2.4.1.patch`;
- `patches/react-native-reanimated+1.13.3.patch`.

Le patch aggiungono esclusivamente i metodi bridge `addListener` e
`removeListeners` alle due classi native risultate responsabili.

La generazione è stata limitata alle sole classi Java, escludendo
artefatti Gradle e metadati Eclipse locali.

## Verifica finale

- build: `labRelease`;
- installazione su `emulator-5554`: completata;
- bundle SDK e bundle APK: identici;
- SHA-256 bundle: `43d851e06a644fc581f9ea826a6571c183dea91cd2970bbdb579e8234ffdddcd`;
- warning `NativeEventEmitter`: **zero**;
- errori runtime rilevanti nel Logcat: **zero**;
- marker diagnostici temporanei: **zero**.

Le prove complete sono conservate in:

- `_BACKUP/native-emitter-final-20260723-233649/full-run.txt`;
- `_BACKUP/native-emitter-final-20260723-233649/logcat.txt`.

`react-native-performance` non è stato modificato perché la diagnosi
runtime ha dimostrato che viene caricato ma non genera questi warning.

## Cronologia

Il commit precedente conserva diagnosi, causa e responsabili prima
dell'intervento.

Questo commit conserva la correzione riproducibile e le verifiche
eseguite sull'APK installato.
