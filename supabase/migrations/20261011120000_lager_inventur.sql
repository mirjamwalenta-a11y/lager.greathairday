-- ════════════════════════════════════════════════════════════
--  LAGER · INVENTUR (V1) – Tabellen, RLS und Chefin-Funktionen
--  Im Supabase SQL-Editor des gemeinsamen Projekts ausführen.
--  Läuft als EINE Transaktion und ist mehrfach ausführbar.
--
--  Grundsätze (CLAUDE.md):
--    * Beide Tabellen haben RLS ab dem Anlegen, anon bekommt nichts.
--    * Wer Chefin ist, entscheidet die Datenbank (abw_is_owner()),
--      nie der Browser.
--    * Inventuren werden nie gelöscht oder überschrieben; Status-
--      wechsel nur über SECURITY-DEFINER-Funktionen.
--
--  Fachlich:
--    * Angemeldete Mitarbeiter:innen dürfen in einer OFFENEN Inventur
--      zählen (anlegen, korrigieren, entfernen). In einer abgeschlossenen
--      Inventur darf das nur die Chefin.
--    * Stichtag frei wählbar beim Start; nachträglich ändern nur die Chefin
--      (siehe auch 20261011130000_lager_inventur_stichtag_bearbeiten.sql).
--    * Abschließen und Wieder-Öffnen: nur die Chefin.
--    * Zählungen einer abgeschlossenen Inventur (= Grundlage für
--      Auswertung und CSV) liest nur die Chefin.
--    * Pro Inventur, Produkt und Ort genau eine Zeile (Primärschlüssel).
--    * Die Produktdaten (Barcode, Name, Firma, Preis, Stück/Gebinde)
--      werden in jede Zählung mitgeschrieben, damit eine abgeschlossene
--      Inventur unverändert bleibt, auch wenn sich Stammdaten ändern.
-- ════════════════════════════════════════════════════════════
BEGIN;

DO $pruef$
BEGIN
  IF to_regprocedure('public.abw_is_owner()') IS NULL THEN
    RAISE EXCEPTION 'Abbruch: abw_is_owner() fehlt – ist das das richtige Supabase-Projekt?';
  END IF;
END $pruef$;

-- ── Inventuren (Kopf) ──────────────────────────────────────────
CREATE TABLE IF NOT EXISTS lager_inventuren (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  stichtag          date NOT NULL DEFAULT current_date,
  status            text NOT NULL DEFAULT 'offen' CHECK (status IN ('offen', 'abgeschlossen')),
  angelegt_am       timestamptz NOT NULL DEFAULT now(),
  angelegt_von      uuid,
  abgeschlossen_am  timestamptz,
  abgeschlossen_von uuid
);
ALTER TABLE lager_inventuren ENABLE ROW LEVEL SECURITY;

-- Höchstens eine offene Inventur gleichzeitig
CREATE UNIQUE INDEX IF NOT EXISTS lager_inventuren_eine_offene
  ON lager_inventuren ((true)) WHERE status = 'offen';

-- ── Zählungen (eine Zeile je Produkt und Ort) ──────────────────
CREATE TABLE IF NOT EXISTS lager_inventur_zaehlungen (
  inventur_id         uuid NOT NULL REFERENCES lager_inventuren(id) ON DELETE RESTRICT,
  produkt_id          text NOT NULL,
  ort                 text NOT NULL CHECK (ort IN ('geschaeft', 'lager')),
  menge               integer NOT NULL CHECK (menge >= 0),
  barcode             text NOT NULL,
  produktname         text NOT NULL,
  produktfirma        text NOT NULL CHECK (produktfirma IN ('Loreal', 'Nashi Argan', 'Goldwell', 'Wella')),
  bruttopreis_gebinde numeric(12,2) NOT NULL CHECK (bruttopreis_gebinde >= 0),
  stueck_gebinde      integer NOT NULL CHECK (stueck_gebinde > 0),
  erfasst_am          timestamptz NOT NULL DEFAULT now(),
  erfasst_von         uuid,
  PRIMARY KEY (inventur_id, produkt_id, ort)
);
ALTER TABLE lager_inventur_zaehlungen ENABLE ROW LEVEL SECURITY;

-- Wer/wann wird vom Server gesetzt, nicht vom Browser
CREATE OR REPLACE FUNCTION lager_inventur_zaehlung_stempel() RETURNS trigger
LANGUAGE plpgsql SET search_path = public AS $$
BEGIN
  NEW.erfasst_am  := now();
  NEW.erfasst_von := auth.uid();
  RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS lager_inventur_zaehlung_stempel ON lager_inventur_zaehlungen;
CREATE TRIGGER lager_inventur_zaehlung_stempel
  BEFORE INSERT OR UPDATE ON lager_inventur_zaehlungen
  FOR EACH ROW EXECUTE FUNCTION lager_inventur_zaehlung_stempel();

-- ── Hilfsfunktionen ────────────────────────────────────────────
CREATE OR REPLACE FUNCTION lager_inventur_ist_offen(p_id uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (SELECT 1 FROM lager_inventuren WHERE id = p_id AND status = 'offen');
$$;

-- Nur für das Ein-/Ausblenden von Knöpfen; abgesichert wird über RLS/Funktionen.
CREATE OR REPLACE FUNCTION lager_ist_chefin() RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT abw_is_owner();
$$;

-- ── Rechte ─────────────────────────────────────────────────────
REVOKE ALL ON lager_inventuren, lager_inventur_zaehlungen FROM anon;
REVOKE ALL ON lager_inventuren FROM authenticated;
GRANT SELECT ON lager_inventuren TO authenticated;
REVOKE ALL ON lager_inventur_zaehlungen FROM authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON lager_inventur_zaehlungen TO authenticated;

-- Inventur-Köpfe: alle Angemeldeten sehen Stichtag/Status.
-- Kein INSERT/UPDATE/DELETE per REST – nur über die Funktionen unten.
DROP POLICY IF EXISTS lager_inventuren_lesen ON lager_inventuren;
CREATE POLICY lager_inventuren_lesen ON lager_inventuren
  FOR SELECT TO authenticated USING (true);

-- Zählungen: offene Inventur für alle Angemeldeten, abgeschlossene nur Chefin
DROP POLICY IF EXISTS lager_inventur_zaehlungen_lesen ON lager_inventur_zaehlungen;
CREATE POLICY lager_inventur_zaehlungen_lesen ON lager_inventur_zaehlungen
  FOR SELECT TO authenticated
  USING (lager_inventur_ist_offen(inventur_id) OR abw_is_owner());

DROP POLICY IF EXISTS lager_inventur_zaehlungen_anlegen ON lager_inventur_zaehlungen;
CREATE POLICY lager_inventur_zaehlungen_anlegen ON lager_inventur_zaehlungen
  FOR INSERT TO authenticated
  WITH CHECK (lager_inventur_ist_offen(inventur_id) OR abw_is_owner());

DROP POLICY IF EXISTS lager_inventur_zaehlungen_aendern ON lager_inventur_zaehlungen;
CREATE POLICY lager_inventur_zaehlungen_aendern ON lager_inventur_zaehlungen
  FOR UPDATE TO authenticated
  USING (lager_inventur_ist_offen(inventur_id) OR abw_is_owner())
  WITH CHECK (lager_inventur_ist_offen(inventur_id) OR abw_is_owner());

DROP POLICY IF EXISTS lager_inventur_zaehlungen_entfernen ON lager_inventur_zaehlungen;
CREATE POLICY lager_inventur_zaehlungen_entfernen ON lager_inventur_zaehlungen
  FOR DELETE TO authenticated
  USING (lager_inventur_ist_offen(inventur_id) OR abw_is_owner());

-- ── Funktionen für Statuswechsel ───────────────────────────────
-- Neue Inventur starten (alle Angemeldeten). Gibt es schon eine offene,
-- wird diese zurückgegeben – es entsteht keine zweite.
DROP FUNCTION IF EXISTS lager_inventur_starten();
CREATE OR REPLACE FUNCTION lager_inventur_starten(p_stichtag date DEFAULT current_date) RETURNS lager_inventuren
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE r lager_inventuren;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Nicht angemeldet'; END IF;
  SELECT * INTO r FROM lager_inventuren WHERE status = 'offen';
  IF FOUND THEN RETURN r; END IF;
  INSERT INTO lager_inventuren (stichtag, angelegt_von)
  VALUES (coalesce(p_stichtag, current_date), auth.uid())
  RETURNING * INTO r;
  RETURN r;
END $$;

-- Stichtag nachträglich ändern: nur die Chefin
CREATE OR REPLACE FUNCTION lager_inventur_stichtag_setzen(p_id uuid, p_stichtag date) RETURNS lager_inventuren
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE r lager_inventuren;
BEGIN
  IF NOT abw_is_owner() THEN RAISE EXCEPTION 'Nur die Chefin'; END IF;
  IF p_stichtag IS NULL THEN RAISE EXCEPTION 'Stichtag fehlt'; END IF;
  UPDATE lager_inventuren SET stichtag = p_stichtag WHERE id = p_id RETURNING * INTO r;
  IF NOT FOUND THEN RAISE EXCEPTION 'Inventur nicht gefunden'; END IF;
  RETURN r;
END $$;

CREATE OR REPLACE FUNCTION lager_inventur_abschliessen(p_id uuid) RETURNS lager_inventuren
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE r lager_inventuren;
BEGIN
  IF NOT abw_is_owner() THEN RAISE EXCEPTION 'Nur die Chefin'; END IF;
  UPDATE lager_inventuren
     SET status = 'abgeschlossen', abgeschlossen_am = now(), abgeschlossen_von = auth.uid()
   WHERE id = p_id AND status = 'offen'
  RETURNING * INTO r;
  IF NOT FOUND THEN RAISE EXCEPTION 'Inventur nicht gefunden oder nicht offen'; END IF;
  RETURN r;
END $$;

CREATE OR REPLACE FUNCTION lager_inventur_wieder_oeffnen(p_id uuid) RETURNS lager_inventuren
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE r lager_inventuren;
BEGIN
  IF NOT abw_is_owner() THEN RAISE EXCEPTION 'Nur die Chefin'; END IF;
  IF EXISTS (SELECT 1 FROM lager_inventuren WHERE status = 'offen') THEN
    RAISE EXCEPTION 'Es gibt bereits eine offene Inventur';
  END IF;
  UPDATE lager_inventuren
     SET status = 'offen', abgeschlossen_am = NULL, abgeschlossen_von = NULL
   WHERE id = p_id AND status = 'abgeschlossen'
  RETURNING * INTO r;
  IF NOT FOUND THEN RAISE EXCEPTION 'Inventur nicht gefunden oder nicht abgeschlossen'; END IF;
  RETURN r;
END $$;

REVOKE ALL ON FUNCTION lager_inventur_ist_offen(uuid), lager_ist_chefin(),
  lager_inventur_starten(date), lager_inventur_stichtag_setzen(uuid, date),
  lager_inventur_abschliessen(uuid), lager_inventur_wieder_oeffnen(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION lager_inventur_ist_offen(uuid), lager_ist_chefin(),
  lager_inventur_starten(date), lager_inventur_stichtag_setzen(uuid, date),
  lager_inventur_abschliessen(uuid), lager_inventur_wieder_oeffnen(uuid) TO authenticated;

COMMIT;
