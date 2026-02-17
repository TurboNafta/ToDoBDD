-- ============================================================
-- PULIZIA E RESET TOTALE
-- ============================================================
--Resetta gli ID in modo che Mario sia 1, Luigi sia 2 ecc.
TRUNCATE TABLE Condivisione, Attivita, Checklist, ToDo, Bacheca, Utente RESTART IDENTITY CASCADE;


-- ============================================================
-- REGISTRAZIONE UTENTI 
-- ============================================================
--parametri: login password

-- ID atteso: 1
SELECT registra_utente('mario_rossi', 'passMario1'); 
-- ID atteso: 2
SELECT registra_utente('luigi_verdi', 'passLuigi2'); 
-- ID atteso: 3
SELECT registra_utente('anna_bianchi', 'passAnna3'); 


-- ============================================================
-- CREAZIONE BACHECHE 
-- ============================================================
-- parametri: Titolo, Descrizione, ID_Utente

-- MARIO (ID 1) crea le sue bacheche
-- ID Bacheca atteso: 1
SELECT crea_bacheca_utente('Lavoro', 'Progetti Ufficio', 1); 
-- ID Bacheca atteso: 2
SELECT crea_bacheca_utente('TempoLibero', 'Sport e Hobby', 1); 

-- LUIGI (ID 2) crea le sue bacheche
-- ID Bacheca atteso: 3
SELECT crea_bacheca_utente('Universita', 'Esami Magistrale', 2); 
-- ID Bacheca atteso: 4
SELECT crea_bacheca_utente('Lavoro', 'Turni Negozio', 2); 


-- ============================================================
-- CREAZIONE TODO
-- ============================================================
-- parametri: Titolo, Desc, Scadenza, Colore, Img, Url, ID_Utente, ID_Bacheca

-- --- TODO DI MARIO (Utente 1) ---

-- Inseriamo in 'Lavoro' (Bacheca 1) -> ID ToDo atteso: 1
SELECT crea_todo_utente(
    'Consegnare Report', 
    'Report mensile vendite', 
    '2024-12-15', 
    'rosso', 
    NULL, 
    NULL, 
    1, 
    1 
);

-- Inseriamo in 'Lavoro' (Bacheca 1) -> ID ToDo atteso: 2
-- (Il trigger calcolerà automaticamente la posizione 2)
SELECT crea_todo_utente(
    'Riunione Team', 
    'Meeting settimanale', 
    '2024-12-20', 
    'blu', 
    NULL, 
    NULL, 
    1, 
    1
);

-- Inseriamo in 'TempoLibero' (Bacheca 2) -> ID ToDo atteso: 3
SELECT crea_todo_utente(
    'Prenotare Calcetto', 
    'Chiamare il centro', 
    '2024-11-30', 
    'verde', 
    NULL, 
    NULL, 
    1, 
    2
);

-- --- TODO DI LUIGI (Utente 2) ---

-- 4. Inseriamo in 'Universita' (Bacheca 3) -> ID ToDo atteso: 4
SELECT crea_todo_utente(
    'Studiare Basi di Dati', 
    'Ripassare SQL', 
    '2025-01-10', 
    'arancione', 
    NULL, 
    NULL, 
    2, 
    3
);


-- ============================================================
-- GESTIONE CHECKLIST 
-- ============================================================
-- Lavoriamo sul ToDo "Studiare Basi di Dati" (ID 4)

-- La funzione crea automaticamente la checklist se non esiste
-- ID Attività atteso: 1
SELECT aggiungi_attivita_checklist(4, 'Capire INSERT');

-- ID Attività atteso: 2
SELECT aggiungi_attivita_checklist(4, 'Scrivere Trigger');

-- ID Attività atteso: 3
SELECT aggiungi_attivita_checklist(4, 'Testare Funzioni');

-- ============================================================
--  MODIFICA STATO ATTIVITÀ 
-- ============================================================
-- Segniamo le prime due come completate.
-- parametri: ID_Attivita, NuovoStato

SELECT modifica_stato_attivita(1, 'Completato'); 
SELECT modifica_stato_attivita(2, 'Completato'); 

-- Verifica Trigger: Il ToDo 4 dovrebbe essere ancora "NonCompletato" perché la 3 è incompleta.


-- ============================================================
-- CONDIVISIONE 
-- ============================================================
-- Parametri: ID_ToDo, Login Autore, Login Destinatario

-- Mario (mario_rossi) condivide "Consegnare Report" (ID 1) con Anna (anna_bianchi).
-- Anna NON ha bacheche. La funzione + trigger creerà per lei la bacheca 'Lavoro'.
SELECT aggiungi_condivisione_todo(1, 'mario_rossi', 'anna_bianchi');

-- Luigi (luigi_verdi) condivide "Studiare Basi di Dati" (ID 4) con Mario (mario_rossi).
-- Mario non ha la bacheca 'Universita'. Il sistema la creerà per lui.
SELECT aggiungi_condivisione_todo(4, 'luigi_verdi', 'mario_rossi');


-- ============================================================
--  MODIFICA E SPOSTAMENTO
-- ============================================================

-- Modifica stato manuale del ToDo 2 (Riunione Team) di Mario
SELECT modifica_stato_todo(2, 'mario_rossi', 'Completato');

-- Spostamento Bacheca: Mario sposta "Prenotare Calcetto" (ID 3) 
-- dalla bacheca 'TempoLibero' a 'Lavoro' (ID 1)
-- Parametri: ID_ToDo, Login, Titolo Nuova, Descrizione Nuova
SELECT cambia_bacheca_todo(3, 'mario_rossi', 'Lavoro', 'Progetti Ufficio');

-- ============================================================
-- TEST DELLA VISTA E FILTRI 
-- ============================================================

-- Ricerca testuale: Trova tutti i ToDo che contengono "Report" (nel titolo o descrizione)
-- Deve trovare il ToDo 1 di Mario e la copia condivisa di Anna
SELECT * FROM filtra_todo_bacheca(1, 'TITOLO', 'Report');

--  Ricerca ToDo in scadenza OGGI
SELECT * FROM filtra_todo_bacheca(1, 'OGGI');

-- Ordinamento per STATO: mostra prima i completati
-- Vedremo il ToDo 2 (Riunione) in cima perché lo abbiamo forzato a 'Completato'
SELECT * FROM visualizza_todo_ordinati(1, 'STATO');

-- ============================================================
-- VISTA DI TUTTI I TODO DI UN UTENTE
-- ============================================================
-- Recupera tutti i todo (sia quelli creati da Mario, sia quelli condivisi con esso)
SELECT * FROM Vista_Bacheca_Unificata WHERE ID_Utente_Visualizzatore = 1;

-- ============================================================
-- TEST DI FALLIMENTO
-- ============================================================

-- .Tentativo di creare una bacheca con titolo non ammesso
-- Deve fallire per il vincolo di checl sul titolo
--SELECT crea_bacheca_utente('Scuola', 'Bacheca non valida', 1);

-- Tentativo di auto-condivisione
-- Deve fallire perché Mario non può condividere il ToDo 1 con se stesso
-- Trigger: trg_prevenire_auto_condivisione
--SELECT aggiungi_condivisione_todo(1, 'mario_rossi', 'mario_rossi');

-- Tentativo di creare una bacheca duplicata (stesso titolo e stessa descrizione)
-- deve fallire per il vincolo UNIQUE: unique_bacheca_desc
--SELECT crea_bacheca_utente('Lavoro', 'Progetti Ufficio', 1);

