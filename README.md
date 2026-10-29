# D. Watch Lab

App Android che stima il valore di un orologio dalle foto, usando l'IA
Google Gemini (piano gratuito). Ispirata al Watch Scanner di Chrono24, con in più
foto multiple, modelli alternativi e segnali di possibile falso.

## Novità v0.2
- Un tocco per valutare: fotografi il quadrante e l'analisi parte subito.
- Attivazione della chiave gratuita direttamente dalla schermata principale
  (apre Google AI Studio e incolla la chiave dagli appunti).
- Schermata di analisi animata con errori chiari e tasto "Riprova".
- Se Google è occupato l'app riprova da sola e cambia modello.
- "Migliora la stima" nel risultato: aggiungi foto, scatola, documenti e
  rivaluta.
- Ultime valutazioni in home, animazioni più fluide.

## Funzioni (v0.1)
- **Foto guidate**: quadrante (obbligatoria), fondello, lato e corona, fibbia,
  anse, scatola/garanzia. Più foto = stima più precisa.
- **Identificazione**: marca, modello, referenza, calibro, periodo, con
  percentuale di certezza e fino a 3 modelli alternativi.
- **Prezzo**: valore probabile dell'usato, forbice minimo–massimo, prezzo del
  nuovo, motivazione, prezzi di confronto e fonti web (ricerca Google attivabile).
- **Segnali di falso**: dettagli sospetti con gravità (non è un'autenticazione).
- **Collezione**: storico delle valutazioni, valore totale, "Aggiorna il valore"
  per seguire l'andamento nel tempo.
- **Annuncio**: copia un testo pronto per vendere l'orologio.

## Come si usa
1. Installa l'APK dalla pagina *Releases* (`app-arm64-v8a-release.apk`).
2. Prendi una chiave gratuita su https://aistudio.google.com/apikey
3. Incollala in **Impostazioni → Verifica e salva**.
4. Scatta la foto del quadrante e tocca **Valuta**.

## Limiti
- Le stime sono indicative: l'IA può sbagliare referenza o prezzo, soprattutto
  con foto scure, riflessi o modelli rari.
- Il piano gratuito di Gemini ha limiti di richieste al minuto/giorno e Google
  può usare le foto per migliorare i suoi modelli.
- I segnali di falso non sostituiscono l'esame di un perito.
- Senza secret di firma l'APK è firmato con una chiave di debug conservata nella
  cache di GitHub: se la cache scade, il nuovo APK va installato dopo aver
  disinstallato il vecchio. Per firme stabili aggiungi i secret
  `SIGNING_KEYSTORE_B64` e `SIGNING_PASSWORD` (alias `app`).
