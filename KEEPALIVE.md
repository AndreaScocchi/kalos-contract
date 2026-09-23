# Branch di keepalive

GitHub disattiva i workflow programmati di un repo pubblico dopo **60 giorni senza attività** nel
repo: è già successo a `notification-cron.yml`, e senza contromisure succederebbe anche al backup
notturno e al controllo della coda (vedi BACKUP.md §5).

Il workflow `.github/workflows/keepalive.yml`, il primo di ogni mese, aggiorna la riga qui sotto e
la committa su questo branch. È attività del repo, quindi il conteggio dei 60 giorni riparte e i
workflow programmati restano accesi.

Questo branch non contiene codice e non va mai mergiato su `main`.

Ultima esecuzione: mai (branch appena creato)
