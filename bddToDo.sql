-- ============================================================
-- PULIZIA INIZIALE DEL DATABASE
-- ============================================================
DROP TABLE IF EXISTS Condivisione CASCADE;
DROP TABLE IF EXISTS Attivita CASCADE;
DROP TABLE IF EXISTS Checklist CASCADE;
DROP TABLE IF EXISTS ToDo CASCADE;
DROP TABLE IF EXISTS Bacheca CASCADE;
DROP TABLE IF EXISTS Utente CASCADE;
DROP VIEW IF EXISTS Vista_Bacheca_Unificata CASCADE;
DROP FUNCTION IF EXISTS aggiungi_attivita_checklist(INT, VARCHAR);

-- ============================================================
-- CREAZIONE TABELLE
-- ============================================================

CREATE TABLE Utente(
	ID_Utente SERIAL PRIMARY KEY,
	login VARCHAR (30) NOT NULL,
	password VARCHAR (30) NOT NULL, 
	CONSTRAINT unique_login UNIQUE(login),
	CONSTRAINT unique_password UNIQUE(password)
);

CREATE TABLE Bacheca (
	ID_Bacheca SERIAL PRIMARY KEY,
	titolo VARCHAR (30) NOT NULL,
	descrizione VARCHAR (100) NOT NULL,
	ID_Utente INT NOT NULL,
	
	FOREIGN KEY (ID_Utente) REFERENCES Utente (ID_Utente) ON DELETE CASCADE,
	CONSTRAINT unique_bacheca_desc UNIQUE(ID_Utente, titolo, descrizione),
	CONSTRAINT check_titolo CHECK(titolo IN ('TempoLibero', 'Universita', 'Lavoro'))
);

CREATE TABLE ToDo (
	ID_ToDo SERIAL PRIMARY KEY,
	descrizione VARCHAR (1000),
	dataScadenza DATE NOT NULL,
	titolo VARCHAR (30) NOT NULL,
	colore VARCHAR (30) NOT NULL,
	posizione INT NOT NULL, 
	immagine VARCHAR (100),
	stato VARCHAR (30) NOT NULL DEFAULT 'NonCompletato',
	url VARCHAR (500),
	ID_Utente INT NOT NULL,
	ID_Bacheca INT NOT NULL,
	
	FOREIGN KEY (ID_Utente) REFERENCES Utente (ID_Utente) ON DELETE CASCADE,
	FOREIGN KEY (ID_Bacheca) REFERENCES Bacheca (ID_Bacheca) ON DELETE CASCADE,

	CONSTRAINT check_statoToDo CHECK (stato IN ('Completato', 'NonCompletato')),
	CONSTRAINT check_colori CHECK (colore IN ('rosso', 'giallo', 'blu', 'verde', 'arancione', 'rosa', 'viola', 'celeste', 'marrone'))
);

CREATE TABLE CHECKLIST(
	ID_Checklist SERIAL PRIMARY KEY,
	ID_ToDo INT NOT NULL,
	
	FOREIGN KEY (ID_ToDo) REFERENCES ToDo (ID_ToDo) ON DELETE CASCADE,
	CONSTRAINT unique_checklist_todo UNIQUE (ID_Todo) -- Un ToDo può avere al massimo una checklist
);
	
CREATE TABLE Attivita(
	ID_Attivita SERIAL PRIMARY KEY,
	nome VARCHAR (30) NOT NULL,
	stato VARCHAR (30) NOT NULL DEFAULT 'NonCompletato',
	ID_Checklist INT NOT NULL,
	
	FOREIGN KEY (ID_Checklist) REFERENCES Checklist (ID_Checklist) ON DELETE CASCADE,
	CONSTRAINT check_statoAttivita CHECK (stato IN ('Completato', 'NonCompletato'))
);

CREATE TABLE Condivisione (
	ID_Utente INT NOT NULL, --Utente che riceve la condivisione
	ID_ToDo INT NOT NULL,   --ToDo condiviso
	
	PRIMARY KEY (ID_Utente, ID_ToDo), -- evita duplicati
	FOREIGN KEY (ID_Utente) REFERENCES Utente (ID_Utente) ON DELETE CASCADE,
	FOREIGN KEY (ID_ToDo) REFERENCES ToDo (ID_ToDo) ON DELETE CASCADE
);

-- ============================================================
-- TRIGGER
-- ============================================================

-- Trigger 1: Aggiornamento automatico stato ToDo in base alla Checklist
-- Se tutte le attività sono completate allora il ToDo è completato altrimenti NonCompletato.
CREATE OR REPLACE FUNCTION aggiorna_stato_todo()
RETURNS TRIGGER AS $$
DECLARE
	v_id_checklist INT;
	v_id_todo INT;
	totale_attivita INT;
	attivita_completate INT;
BEGIN
	-- Capisco su quale checklist stiamo lavorando (insert, update o delete)
	IF (TG_OP = 'DELETE') THEN
		v_id_checklist := OLD.ID_Checklist;
	ELSE
		v_id_checklist := NEW.ID_Checklist;
	END IF;
	-- Risalgo al ToDo padre
	SELECT ID_ToDo INTO v_id_todo
	FROM Checklist
	WHERE ID_Checklist = v_id_checklist;

	IF v_id_todo IS NULL THEN 
		RETURN NULL;
    END IF;
	
	-- Conto le attività in totale
	SELECT COUNT(*) INTO totale_attivita
	FROM Attivita
	WHERE ID_Checklist = v_id_checklist;
	
	--Conto quelle già fatte
	SELECT COUNT(*) INTO attivita_completate
	FROM Attivita
	WHERE ID_Checklist = v_id_checklist AND stato = 'Completato';
	
	-- Se il totale > 0 e sono tutte fatte allora il ToDo è completo
	IF (totale_attivita > 0 AND totale_attivita = attivita_completate) THEN
		UPDATE ToDo
		SET stato = 'Completato'
		WHERE ID_ToDo = v_id_todo AND stato <> 'Completato';
	ELSE -- altrimenti non è completo
		UPDATE ToDo
		SET stato = 'NonCompletato'
		WHERE ID_ToDo = v_id_todo AND stato <> 'NonCompletato';
	END IF;

	RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_aggiorna_todo
AFTER INSERT OR UPDATE OR DELETE ON Attivita
FOR EACH ROW
EXECUTE FUNCTION aggiorna_stato_todo();

-- Trigger 2: gestione della condivisione
--Crea una copia della bacheca dell'utente che condivide il todo, 
--e l'aggiunge tra quelle dell'utente con cui ha condiviso il todo
CREATE OR REPLACE FUNCTION check_creazione_bacheca_condivisione() 
RETURNS TRIGGER AS $$
DECLARE
    v_titolo_orig VARCHAR(30);
    v_desc_orig VARCHAR(100);
	v_esiste INT;
BEGIN
    -- Recupero sia il titolo che la descrizione dalla bacheca originale 
    SELECT B.titolo, B.descrizione 
    INTO v_titolo_orig, v_desc_orig
    FROM ToDo T
    JOIN Bacheca B ON T.ID_Bacheca = B.ID_Bacheca
    WHERE T.ID_ToDo = NEW.ID_ToDo;

	--Controllo se esiste una bacheca con lo stesso titolo
	SELECT ID_Bacheca INTO v_esiste
	FROM Bacheca
	WHERE ID_Utente = NEW.ID_Utente AND titolo = v_titolo_orig
	LIMIT 1;--basta una
    -- Se NON esiste nessuna bacheca con quel titolo, allora la creo
	IF v_esiste IS NULL THEN
   		INSERT INTO Bacheca (titolo, descrizione, ID_Utente)
    	VALUES (v_titolo_orig, v_desc_orig, NEW.ID_Utente);
    	RAISE NOTICE 'Creata nuova bacheca % per utente %', v_titolo_orig, NEW.ID_Utente;
	END IF;
	
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_check_condivisione
BEFORE INSERT ON Condivisione
FOR EACH ROW
EXECUTE FUNCTION check_creazione_bacheca_condivisione();

-- Trigger 3: Prevenire auto-condivisione
-- Impedisce di condividere un task con se stessi.
CREATE OR REPLACE FUNCTION prevenire_auto_condivisione()
RETURNS TRIGGER AS $$
DECLARE
    v_id_autore INT;
BEGIN
	--trovo chi ha creato il todo
    SELECT ID_Utente INTO v_id_autore 
	FROM ToDo 
	WHERE ID_ToDo = NEW.ID_ToDo;
    
	--se chi riceve è lo stesso che ha creato allora errore
    IF NEW.ID_Utente = v_id_autore THEN
        RAISE EXCEPTION 'Non puoi condividere un ToDo con te stesso (sei già l''autore).';
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_prevenire_auto_condivisione
BEFORE INSERT ON Condivisione
FOR EACH ROW
EXECUTE FUNCTION prevenire_auto_condivisione();

-- Trigger 4:Ordine automatico (Inserimento)
-- Quando creo un ToDo, lo mette automaticamente in fondo alla lista.
CREATE OR REPLACE FUNCTION return_max_posizione()
RETURNS TRIGGER AS $$
DECLARE 
	max_pos INT;
BEGIN 
	--calcolo il massimo numero di posizione ed aggiungo 1
	SELECT MAX(Posizione) INTO max_pos
    FROM ToDo
    WHERE ID_Bacheca = NEW.ID_Bacheca;

    NEW.Posizione := COALESCE(max_pos, 0) + 1;
	RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_set_posizione_todo
BEFORE INSERT OR UPDATE OF ID_Bacheca ON ToDo
FOR EACH ROW
EXECUTE FUNCTION return_max_posizione();

-- Trigger 5: Ordine automatico (Cancellazione)
CREATE OR REPLACE FUNCTION riordina_posizioni_delete()
RETURNS TRIGGER AS $$
BEGIN
    -- prende tutti i todo che stavano dopo quello cancellato 
    -- e scala la loro posizione di -1
    UPDATE ToDo
    SET posizione = posizione - 1
    WHERE ID_Bacheca = OLD.ID_Bacheca
      AND posizione > OLD.posizione;
      
    RETURN OLD;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_riordina_dopo_delete
AFTER DELETE ON ToDo
FOR EACH ROW
EXECUTE FUNCTION riordina_posizioni_delete();

-- ============================================================
-- VISTA
-- ============================================================

-- Questa vista unifica i ToDo creati dall'utente e quelli condivisi con esso.
CREATE VIEW Vista_Bacheca_Unificata AS
-- ToDo propri
SELECT 
    T.ID_ToDo,
    T.titolo AS Nome_ToDo,
    T.descrizione,
    T.dataScadenza,
    T.stato,
    T.colore,
	T.immagine,
	T.url,
	T.posizione,
    T.ID_Utente AS ID_Autore,
    B.ID_Utente AS ID_Utente_Visualizzatore,
    B.ID_Bacheca AS ID_Bacheca_Visualizzazione,
    B.titolo AS Titolo_Bacheca,
	B.descrizione AS Descrizione_Bacheca
FROM ToDo T
JOIN Bacheca B ON T.ID_Bacheca = B.ID_Bacheca

UNION ALL

--ToDo condivisi
SELECT 
    T.ID_ToDo,
    T.titolo AS Nome_ToDo,
    T.descrizione,
    T.dataScadenza,
    T.stato,
    T.colore,
	T.immagine,
	T.url,
	T.posizione,
    T.ID_Utente AS ID_Autore,
    C.ID_Utente AS ID_Utente_Visualizzatore,
    B_Clone.ID_Bacheca AS ID_Bacheca_Visualizzazione,
    B_Clone.titolo AS Categoria_Bacheca,
	B_Clone.descrizione AS Descrizione_Bacheca
FROM Condivisione C
JOIN ToDo T ON C.ID_ToDo = T.ID_ToDo
JOIN Bacheca B_Originale ON T.ID_Bacheca = B_Originale.ID_Bacheca
JOIN Bacheca B_Clone ON 
    B_Clone.ID_Utente = C.ID_Utente 
    AND B_Clone.titolo = B_Originale.titolo

-- ============================================================
-- FUNZIONI
-- ============================================================
-- Crea l'utente e mi ridà l'ID.
CREATE OR REPLACE FUNCTION registra_utente(
	p_login VARCHAR (30),
	p_password VARCHAR (30)
)
RETURNS INT AS $$
DECLARE
	v_id_utente INT;
BEGIN
	INSERT INTO Utente (login, password)
	VALUES (p_login, p_password)
	RETURNING ID_Utente INTO v_id_utente;

	RETURN v_id_utente;
EXCEPTION
	WHEN unique_violation THEN
		RETURN -1; -- Ritorna -1 se il login esiste già
END;
$$ LANGUAGE plpgsql;

-- Creazione bacheca. 
CREATE OR REPLACE FUNCTION crea_bacheca_utente(
	p_titolo VARCHAR (30),
	p_descrizione VARCHAR (100),
	p_id_utente INT
)
RETURNS INT AS $$
DECLARE
	v_esiste INT;
	v_nuovo_id INT;
BEGIN
	-- Verifica se esiste già una bacheca con lo stesso titolo per questo utente
	SELECT COUNT (*) INTO v_esiste
	FROM Bacheca
	WHERE ID_Utente = p_id_utente AND titolo = p_titolo AND descrizione = p_descrizione;

	IF v_esiste > 0 THEN
		RETURN -1; -- Errore: Bacheca duplicata
	END IF;
	--creo la bacheca
	INSERT INTO Bacheca (titolo, descrizione, ID_Utente)
	VALUES(p_titolo, p_descrizione, p_id_utente)
	RETURNING ID_Bacheca INTO v_nuovo_id;

	RETURN v_nuovo_id;
EXCEPTION
	WHEN check_violation THEN
		RAISE NOTICE 'Errore: Il titolo deve essere Universita, Lavoro o TempoLibero';
		RETURN -2;
END;
$$ LANGUAGE plpgsql;

--Modifica della bacheca: nome, descrizione
CREATE OR REPLACE FUNCTION modifica_bacheca_utente(
	p_id_bacheca INT,
	p_nuovo_titolo VARCHAR(30),
	p_nuova_descrizione VARCHAR(100)
)
RETURNS BOOLEAN AS $$
DECLARE
	v_id_utente INT;
	v_count INT;
BEGIN
	-- recupera l'utente proprietario della bacheca
	SELECT ID_Utente INTO v_id_utente
	FROM Bacheca
	WHERE ID_Bacheca = p_id_bacheca;

	IF v_id_utente IS NULL THEN
		RETURN FALSE; -- Bacheca non trovata
	END IF;

	-- Verifica che non esistano altre bacheche dello stesso utente col nuovo nome
	SELECT COUNT(*) INTO v_count
	FROM Bacheca
	WHERE ID_Utente = v_id_utente
		AND titolo = p_nuovo_titolo
		AND descrizione = p_descrizione
		AND ID_Bacheca <> p_id_bacheca;

	IF v_count > 0 THEN
		RETURN FALSE; -- Nome e descrizione già in uso
	END IF;
	--modifica
	UPDATE Bacheca
	SET titolo = p_nuovo_titolo,
		descrizione = p_nuova_descrizione
	WHERE ID_Bacheca = p_id_bacheca;

	RETURN TRUE;
	
EXCEPTION
	WHEN check_violation THEN-- deve essere tra quelli di (Universita, Lavoro,TempoLibero)
		RAISE NOTICE 'Errore: Titolo non valido.';
		RETURN FALSE;
END;
$$ LANGUAGE plpgsql;

--Elimino la bacheca (e a cascata i ToDo)
CREATE OR REPLACE FUNCTION elimina_bacheca_utente(
	p_id_bacheca INT
)
RETURNS BOOLEAN AS $$
BEGIN
	DELETE FROM Bacheca
	WHERE ID_Bacheca = p_id_bacheca;

	IF FOUND THEN
		RETURN TRUE;
	ELSE
		RETURN FALSE;
	END IF;
END;
$$ LANGUAGE plpgsql;
--Creazione di un ToDo
CREATE OR REPLACE FUNCTION crea_todo_utente(
	p_titolo VARCHAR(30),
	p_descrizione VARCHAR(1000),
	p_data_scadenza DATE,
	p_colore VARCHAR(30),
	p_immagine VARCHAR(100),
	p_url VARCHAR(500),
	p_id_utente INT,
	p_id_bacheca INT
)
RETURNS INT AS $$
DECLARE
	v_new_id INT;
BEGIN
	INSERT INTO ToDo (
		titolo,
		descrizione,
		dataScadenza,
		colore,
		immagine,
		url,
		ID_Utente,
		ID_Bacheca,
		posizione -- posizione calcolata dal trigger
	)
	VALUES (
		p_titolo,
		p_descrizione,
		p_data_scadenza,
		p_colore,
		p_immagine,
		p_url,
		p_id_utente,
		p_id_bacheca,
		0 --il trigger lo sovrascriverà
	)
	RETURNING ID_ToDo INTO v_new_id;
	RETURN v_new_id;

EXCEPTION
	WHEN check_violation THEN
		RAISE NOTICE 'Errore: Colore non valido o vincolo violato.';
		RETURN -1;
	WHEN foreign_key_violation THEN
		RAISE NOTICE 'Errore: Bacheca o Utente non esistenti.';
		RETURN -2;
END;
$$ LANGUAGE plpgsql;

--Modifica i dati principali di un ToDo
CREATE OR REPLACE FUNCTION modifica_todo_utente(
	p_id_todo INT,
	p_titolo VARCHAR(30),
	p_descrizione VARCHAR(1000),
	p_data_scadenza DATE,
	p_colore VARCHAR(30),
	p_immagine VARCHAR(100),
	p_url VARCHAR(500),
	p_stato VARCHAR(30)
)
RETURNS BOOLEAN AS $$
BEGIN
	UPDATE ToDo
	SET titolo = p_titolo,
		descrizione = p_descrizione,
		dataScadenza = p_data_scadenza,
		colore = p_colore,
		immagine = p_immagine,
		url = p_url,
		stato = p_stato
	WHERE ID_ToDo = p_id_todo;

	IF FOUND THEN
		RETURN TRUE;
	ELSE
		RETURN FALSE;
	END IF;
	
EXCEPTION
	WHEN check_violation THEN
		RAISE NOTICE 'Errore: Colore o Stato non validi.';
		RETURN FALSE;
END;
$$ LANGUAGE plpgsql;

--Cancello un ToDo( e in cascata la sua checklist e condivisioni)
CREATE OR REPLACE FUNCTION elimina_todo_utente(
	p_id_todo INT
)
RETURNS BOOLEAN AS $$
BEGIN
	DELETE FROM ToDo
	WHERE ID_ToDo = p_id_todo;

	IF FOUND THEN
		RETURN TRUE;
	ELSE
		RETURN FALSE;
	END IF;
END;
$$ LANGUAGE plpgsql;

--Controlla se login e passwword coincidono e mi restituisce l'id
CREATE OR REPLACE FUNCTION login_utente(
    p_login VARCHAR(30), 
    p_password VARCHAR(30)
) 
RETURNS INT AS $$
DECLARE
    v_id_utente INT;
BEGIN
    SELECT ID_Utente INTO v_id_utente
    FROM Utente
    WHERE login = p_login AND password = p_password;
    
    IF FOUND THEN
        RETURN v_id_utente;--corrispondono
    ELSE
        RETURN -1;--fallito
    END IF;
END;
$$ LANGUAGE plpgsql;

--Funzione che restituisce il login degli utenti con i quali
--è stato condviso il todo
CREATE OR REPLACE FUNCTION visualizza_condivisioni_todo(
    p_id_todo INT
) 
RETURNS TABLE (
    login_utente VARCHAR
) AS $$
BEGIN
    RETURN QUERY
    SELECT U.login
    FROM Condivisione C
    JOIN Utente U ON C.ID_Utente = U.ID_Utente
    WHERE C.ID_ToDo = p_id_todo;
END;
$$ LANGUAGE plpgsql;

--Elenco bacheche di un utente
CREATE OR REPLACE FUNCTION visualizza_bacheche_utente(
    p_id_utente INT
)
RETURNS TABLE (
    ID_Bacheca INT,
    Titolo VARCHAR,
    Descrizione VARCHAR
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        B.ID_Bacheca,
        B.titolo,
        B.descrizione 
    FROM Bacheca B
    WHERE B.ID_Utente = p_id_utente
    ORDER BY B.ID_Bacheca ASC;
END;
$$ LANGUAGE plpgsql;

--funzione per filtrare e ricercare i todo all'interno della bacheca
CREATE OR REPLACE FUNCTION filtra_todo_bacheca(
    p_id_bacheca INT,
    p_criterio VARCHAR,-- 'TUTTO', 'TITOLO', 'OGGI', 'ENTRO'
    p_filtro_testo VARCHAR DEFAULT NULL, 
    p_filtro_data DATE DEFAULT NULL 
)
RETURNS TABLE (
    ID_ToDo INT, 
    Titolo VARCHAR, 
    Descrizione VARCHAR, 
    DataScadenza DATE, 
    Stato VARCHAR, 
    Colore VARCHAR, 
    Immagine VARCHAR, 
    Url VARCHAR, 
    Posizione INT
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        v.ID_ToDo, 
        v.Nome_ToDo, 
        v.Descrizione, 
        v.DataScadenza, 
        v.Stato, 
        v.Colore, 
        v.Immagine, 
        v.Url, 
		v.Posizione
    FROM Vista_Bacheca_Unificata v
    WHERE v.ID_Bacheca_Visualizzazione = p_id_bacheca 
    AND (
        (p_criterio = 'TUTTO')-- nessun criterio, mostro tutto
        OR 
        (p_criterio = 'TITOLO' AND (--ricerca qualsiasi parola nel titolo o nella descrizione
            v.Titolo ILIKE '%' || COALESCE(p_filtro_testo, '') || '%' OR 
            v.Descrizione ILIKE '%' || COALESCE(p_filtro_testo, '') || '%'
        ))
        OR
        (p_criterio = 'OGGI' AND v.DataScadenza = CURRENT_DATE)
        OR
        (p_criterio = 'ENTRO' AND v.DataScadenza <= p_filtro_data)
    )
    ORDER BY v.Posizione ASC; 
END;
$$ LANGUAGE plpgsql;

--Funzione che serve a visualizzare la checklist relativa ad un todo
CREATE OR REPLACE FUNCTION visualizza_checklist_todo(
    p_id_todo INT
)
RETURNS TABLE (
    ID_Attivita INT,
    Nome VARCHAR,
    Stato VARCHAR
) AS $$
BEGIN
    RETURN QUERY
    SELECT A.ID_Attivita, A.nome, A.stato
    FROM Attivita A
    JOIN Checklist C ON A.ID_Checklist = C.ID_Checklist
    WHERE C.ID_ToDo = p_id_todo
    ORDER BY A.ID_Attivita ASC;
END;
$$ LANGUAGE plpgsql;

--aggiunge un'attività alla checklist
CREATE OR REPLACE FUNCTION aggiungi_attivita_checklist(
    p_id_todo INT,
    p_nome_attivita VARCHAR
)
RETURNS INT AS $$
DECLARE
    v_id_checklist INT;
    v_id_attivita INT;
BEGIN
    -- cerca l'ID della Checklist associata a questo ToDo
    SELECT ID_Checklist INTO v_id_checklist 
    FROM Checklist 
    WHERE ID_ToDo = p_id_todo;

    -- se non esiste (è la prima attività da inserire), crea la riga in checklist
    IF v_id_checklist IS NULL THEN
        INSERT INTO Checklist (ID_ToDo) 
        VALUES (p_id_todo) 
        RETURNING ID_Checklist INTO v_id_checklist;
    END IF;

    -- inserisce l'attività e restituisce l'ID
    INSERT INTO Attivita (nome, ID_Checklist, stato)
    VALUES (p_nome_attivita, v_id_checklist, 'NonCompletato')
    RETURNING ID_Attivita INTO v_id_attivita;

    RETURN v_id_attivita;
END;
$$ LANGUAGE plpgsql;

-- Cambio stato di una voce checklist (Completato/NonCompletato).
CREATE OR REPLACE FUNCTION modifica_stato_attivita(
    p_id_attivita INT,
    p_nuovo_stato VARCHAR
)
RETURNS VOID AS $$
BEGIN
    UPDATE Attivita
    SET stato = p_nuovo_stato
    WHERE ID_Attivita = p_id_attivita;
END;
$$ LANGUAGE plpgsql;

-- Rimuove un'attività dalla checklist.
CREATE OR REPLACE FUNCTION elimina_attivita(
    p_id_attivita INT
)
RETURNS VOID AS $$
BEGIN
    DELETE FROM Attivita 
    WHERE ID_Attivita = p_id_attivita;
END;
$$ LANGUAGE plpgsql;

--Funzione per ordinare i todo in base a vari criteri
CREATE OR REPLACE FUNCTION visualizza_todo_ordinati(
    p_id_bacheca INT,
    p_criterio VARCHAR -- 'POSIZIONE', 'TITOLO', 'DATA', 'STATO'
)
RETURNS TABLE (
    ID_ToDo INT, 
    Titolo VARCHAR, 
    Descrizione VARCHAR, 
    DataScadenza DATE, 
    Stato VARCHAR, 
    Colore VARCHAR, 
    Immagine VARCHAR, 
    Url VARCHAR, 
    Posizione INT
) AS $$
BEGIN 
    RETURN QUERY
    SELECT 
        v.ID_ToDo, 
        v.Nome_ToDo, 
        v.Descrizione, 
        v.DataScadenza, 
        v.Stato, 
        v.Colore, 
        v.Immagine, 
        v.Url, 
        v.Posizione
    FROM Vista_Bacheca_Unificata v -- comprendo anche i condivisi
    WHERE v.ID_Bacheca_Visualizzazione = p_id_bacheca
    ORDER BY
        CASE WHEN p_criterio = 'POSIZIONE' THEN v.Posizione END ASC,
        CASE WHEN p_criterio = 'TITOLO' THEN v.Nome_ToDo END ASC,
        CASE WHEN p_criterio = 'DATA' THEN v.DataScadenza END ASC,
        CASE WHEN p_criterio = 'STATO' THEN 
            CASE v.Stato 
                WHEN 'Completato' THEN 1 
                WHEN 'NonCompletato' THEN 2 
                ELSE 3 
            END 
        END ASC,
        v.Posizione ASC; 
END;
$$ LANGUAGE plpgsql;

--Sposto un todo in un altra bacheca
CREATE OR REPLACE FUNCTION cambia_bacheca_todo(
	p_id_todo INT,
    p_login_utente VARCHAR(30),
    p_titolo_nuova_bacheca VARCHAR(30),
    p_descrizione_nuova_bacheca VARCHAR(100)
)
RETURNS VOID AS $$
DECLARE
    v_id_utente INT;
    v_id_nuova_bacheca INT;
    v_id_vecchia_bacheca INT;
    v_vecchia_posizione INT;
BEGIN
	--verifica esistenza utente
    SELECT ID_Utente INTO v_id_utente
    FROM Utente 
    WHERE login = p_login_utente;
    IF v_id_utente IS NULL THEN
        RAISE EXCEPTION 'Utente "%" non trovato.', p_login_utente;
    END IF;

	--verfica esistenza Todo
	SELECT ID_Bacheca, Posizione INTO v_id_vecchia_bacheca, v_vecchia_posizione
	FROM ToDo
	WHERE ID_ToDo = p_id_todo AND ID_Utente = v_id_utente;

	IF NOT FOUND THEN
		RAISE EXCEPTION 'ToDo con ID % non trovato o non appartente all''utente %.', p_id_todo, p_login_utente;
    END IF;

	--verifica esistenza Bacheca
    SELECT ID_Bacheca INTO v_id_nuova_bacheca
    FROM Bacheca
    WHERE titolo = p_titolo_nuova_bacheca 
      AND descrizione = p_descrizione_nuova_bacheca
      AND ID_Utente = v_id_utente;

    IF v_id_nuova_bacheca IS NULL THEN
        RAISE EXCEPTION 'Nessuna bacheca trovata con titolo "%" e descrizione "%" per l''utente %.', 
        p_titolo_nuova_bacheca, p_descrizione_nuova_bacheca, p_login_utente;
    END IF;

	IF v_id_vecchia_bacheca = v_id_nuova_bacheca THEN
		RETURN;
	END IF;

	--Sposto il todo in una nuova bacheca
    UPDATE ToDo 
    SET ID_Bacheca = v_id_nuova_bacheca
    WHERE ID_ToDo = p_id_todo;

	--tappo il buco di posizione lasciato nella vecchia bacheca
    UPDATE ToDo
    SET Posizione = Posizione - 1
    WHERE ID_Bacheca = v_id_vecchia_bacheca
      AND Posizione > v_vecchia_posizione;
END;
$$ LANGUAGE plpgsql;

--Funzione che permette adun autore di condividere il proprio todo
CREATE OR REPLACE FUNCTION aggiungi_condivisione_todo(
    p_id_todo INT,
    p_login_autore VARCHAR(30),
    p_login_destinatario VARCHAR(30)
)
RETURNS VOID AS $$
DECLARE
    v_id_autore INT;
    v_id_destinatario INT;
BEGIN
    -- recupero ID autore e destinatario
    SELECT ID_Utente INTO v_id_autore FROM Utente WHERE login = p_login_autore;
    SELECT ID_Utente INTO v_id_destinatario FROM Utente WHERE login = p_login_destinatario;
    
    IF v_id_autore IS NULL OR v_id_destinatario IS NULL THEN 
        RAISE EXCEPTION 'Utenti non trovati.'; 
    END IF;
    
    IF v_id_autore = v_id_destinatario THEN
        RAISE EXCEPTION 'Non puoi condividere con te stesso.';
    END IF;

    -- controllo che il ToDo sia dell'autore
    PERFORM 1 FROM ToDo WHERE ID_ToDo = p_id_todo AND ID_Utente = v_id_autore;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'ToDo non trovato o non tuo.';
    END IF;

    -- controllo se già condiviso(non tengo conto dei dati trovati)
    PERFORM 1 FROM Condivisione WHERE ID_Utente = v_id_destinatario AND ID_ToDo = p_id_todo;
    IF FOUND THEN
        RAISE NOTICE 'Già condiviso.';
        RETURN;
    END IF;

    -- inserimento (farà scattare il trigger che crea la bacheca copia)
    INSERT INTO Condivisione (ID_Utente, ID_ToDo)
    VALUES (v_id_destinatario, p_id_todo);
END;
$$ LANGUAGE plpgsql;

-- Sposto la condivisione da un utente a un altro.
	CREATE OR REPLACE FUNCTION modifica_condivisione_todo(
    p_id_todo INT,
    p_login_autore VARCHAR(30),
    p_login_vecchio_destinatario VARCHAR(30),
    p_login_nuovo_destinatario VARCHAR(30)
)
RETURNS VOID AS $$
DECLARE
    v_id_autore INT;
    v_id_vecchio_dest INT;
    v_id_nuovo_dest INT;
BEGIN
    -- recupero ID autore, vecchio destinatario e nuovo
    SELECT ID_Utente INTO v_id_autore FROM Utente WHERE login = p_login_autore;
    SELECT ID_Utente INTO v_id_vecchio_dest FROM Utente WHERE login = p_login_vecchio_destinatario;
    SELECT ID_Utente INTO v_id_nuovo_dest FROM Utente WHERE login = p_login_nuovo_destinatario;
    
    IF v_id_autore IS NULL OR v_id_vecchio_dest IS NULL OR v_id_nuovo_dest IS NULL THEN 
        RAISE EXCEPTION 'Utenti non trovati.'; 
    END IF;

    -- controllo delle proprietà
    PERFORM 1 FROM ToDo WHERE ID_ToDo = p_id_todo AND ID_Utente = v_id_autore;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'ToDo non trovato.';
    END IF;

    -- controllo vecchia condivisione
    PERFORM 1 FROM Condivisione WHERE ID_Utente = v_id_vecchio_dest AND ID_ToDo = p_id_todo;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Non era condiviso con %.', p_login_vecchio_destinatario;
    END IF;

    -- scambio dei destinatari 
    DELETE FROM Condivisione WHERE ID_Utente = v_id_vecchio_dest AND ID_ToDo = p_id_todo;
    
    -- inserisco il nuovo (Il trigger creerà la bacheca clonata per il nuovo utente)
    INSERT INTO Condivisione (ID_Utente, ID_ToDo) VALUES (v_id_nuovo_dest, p_id_todo);
    
    RAISE NOTICE 'Condivisione spostata.';
END;
$$ LANGUAGE plpgsql;

--Funzione che elimina una condivisione
CREATE OR REPLACE FUNCTION elimina_condivisione_todo(
    p_id_todo INT,
    p_login_autore VARCHAR(30),
    p_login_destinatario VARCHAR(30)
)
RETURNS VOID AS $$
DECLARE
    v_id_autore INT;
    v_id_destinatario INT;
BEGIN
    SELECT ID_Utente INTO v_id_autore 
    FROM Utente 
    WHERE login = p_login_autore;

	SELECT ID_Utente INTO v_id_destinatario
	FROM Utente
	WHERE login = p_login_destinatario;

    IF v_id_autore IS NULL OR v_id_destinatario IS NULL THEN 
        RAISE EXCEPTION 'Utente non trovato.'; 
    END IF;

    PERFORM 1 FROM ToDo WHERE ID_ToDo = p_id_todo AND ID_Utente = v_id_autore;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'ToDo non trovato o non di proprietà dell''autore.';
    END IF;

    DELETE FROM Condivisione 
    WHERE ID_Utente = v_id_destinatario AND ID_ToDo = p_id_todo;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Nessuna condivisione trovata.';
    ELSE
        RAISE NOTICE 'Condivisione rimossa.';
    END IF;
END;
$$ LANGUAGE plpgsql;

--Funzione che forza lo stato del todo a mano senza passare per la checklist
CREATE OR REPLACE FUNCTION modifica_stato_todo(
    p_id_todo INT,
    p_login_utente VARCHAR(30),
    p_nuovo_stato VARCHAR(30)
)
RETURNS VOID AS $$
DECLARE
    v_id_utente INT;
BEGIN
    -- Controllo se lo stato è accettato
    IF p_nuovo_stato NOT IN ('Completato', 'NonCompletato') THEN
        RAISE EXCEPTION 'Stato non valido. I valori ammessi sono "Completato" o "NonCompletato".';
    END IF;

    -- Recupero ID Utente
    SELECT ID_Utente INTO v_id_utente 
    FROM Utente 
    WHERE login = p_login_utente;
	
    -- Verifica proprietà e aggiorno stato del ToDo
    UPDATE ToDo
    SET stato = p_nuovo_stato
    WHERE ID_ToDo = p_id_todo AND ID_Utente = v_id_utente;

	IF NOT FOUND THEN
        RAISE EXCEPTION 'ToDo non trovato o non appartenente all''utente.';
    ELSE
        RAISE NOTICE 'ToDo segnato come %.', p_nuovo_stato;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- Funzione per cambiare la posizione di un ToDo nella stessa bacheca 
-- gestisce lo spostamento di tutti gli altri ToDo per fare spazio.
CREATE OR REPLACE FUNCTION sposta_todo_posizione(
    p_id_todo INT,
    p_nuova_posizione INT
)
RETURNS VOID AS $$
DECLARE
    v_id_bacheca INT;
    v_vecchia_posizione INT;
BEGIN
    -- Recupera posizione attuale e bacheca
    SELECT ID_Bacheca, Posizione 
    INTO v_id_bacheca, v_vecchia_posizione
    FROM ToDo
    WHERE ID_ToDo = p_id_todo;

    -- Controlla se il todo esiste
    IF NOT FOUND THEN
        RAISE EXCEPTION 'ToDo con ID % non trovato.', p_id_todo;
    END IF;

    -- Se la posizione non cambia, esci
    IF v_vecchia_posizione = p_nuova_posizione THEN
        RETURN;
    END IF;

    -- Sposta gli altri ToDo per fare spazio
    IF v_vecchia_posizione < p_nuova_posizione THEN
        -- Spostamento verso il basso (es. da 2 a 5)
        UPDATE ToDo
        SET Posizione = Posizione - 1
        WHERE ID_Bacheca = v_id_bacheca
          AND Posizione > v_vecchia_posizione 
          AND Posizione <= p_nuova_posizione;
    ELSE
        -- Spostamento verso l'alto (es. da 5 a 2)
        UPDATE ToDo
        SET Posizione = Posizione + 1
        WHERE ID_Bacheca = v_id_bacheca
          AND Posizione >= p_nuova_posizione 
          AND Posizione < v_vecchia_posizione;
    END IF;

    -- Aggiorna il ToDo target alla nuova posizione
    UPDATE ToDo
    SET Posizione = p_nuova_posizione
    WHERE ID_ToDo = p_id_todo;
    
    RAISE NOTICE 'ToDo spostato dalla posizione % alla %.', v_vecchia_posizione, p_nuova_posizione;
END;

$$ LANGUAGE plpgsql;

