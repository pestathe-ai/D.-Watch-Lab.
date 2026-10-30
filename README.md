# D. Watch Lab

App Android che stima il valore di un orologio dalle foto, usando l'IA
Google Gemini (piano gratuito). Ispirata al Watch Scanner di Chrono24, con in più
foto multiple, modelli alternativi e segnali di possibile falso.

## Novità v0.5
- **Prezzo in pochi secondi**: un primo riconoscimento lampo (solo marca,
  modello, referenza) fa partire subito la ricerca eBay; l'analisi completa
  (condizioni, segnali di falso) corre in parallelo e si aggiunge dopo.
- Se l'analisi completa riconosce un modello diverso, il prezzo eBay viene
  ricalcolato da solo.
- Ricerche eBay tutte in parallelo e memorizzate per 24 ore.
- Modalità veloce (Impostazioni), foto più leggere.
- Icona famiglia D. con orologio stile Tank, firma "un'app Dom Studio".
- **Riserva IA gratuita** (Impostazioni → Riserva IA): se Gemini è al limite
  l'app passa da sola a chiavi Gemini di altri progetti e poi a Groq,
  OpenRouter o Mistral (piani gratuiti).

## Novità v0.3
- **Prezzo da annunci reali**: dopo il riconoscimento l'app legge gli annunci
  eBay di Italia e Germania (API gratuita), scarta cinturini, ricambi, lotti e
  prezzi fuori scala e calcola una mediana ponderata (gli usati pesano più dei
  nuovi). Mostra quanti annunci ha usato e li elenca.
- **Chrono24, Subito, eBay e Catawiki dentro l'app** con la ricerca già pronta
  (Chrono24 ordinato per prezzo crescente).
- **Più veloce**: foto più leggere e ragionamento dell'IA ridotto.
- L'IA non sottostima più: senza annunci usa il prezzo tipico di mercato.

Per i prezzi reali servono App ID e Cert ID gratuiti da
https://developer.ebay.com/my/keys (Impostazioni → Prezzi reali da eBay).

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
- L'API gratuita di eBay mostra gli annunci attivi (prezzi richiesti), non i
  venduti. Chrono24 non ha un'API pubblica: lo apri dentro l'app ma il suo
  prezzo non entra nel calcolo automatico.
- Le stime sono indicative: l'IA può sbagliare referenza o prezzo, soprattutto
  con foto scure, riflessi o modelli rari.
- Il piano gratuito di Gemini ha limiti di richieste al minuto/giorno e Google
  può usare le foto per migliorare i suoi modelli.
- I segnali di falso non sostituiscono l'esame di un perito.
- Senza secret di firma l'APK è firmato con una chiave di debug conservata nella
  cache di GitHub: se la cache scade, il nuovo APK va installato dopo aver
  disinstallato il vecchio. Per firme stabili aggiungi i secret
  `SIGNING_KEYSTORE_B64` e `SIGNING_PASSWORD` (alias `app`).
