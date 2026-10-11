-- ════════════════════════════════════════════════════════════
--  LAGER · INVENTUR – Stichtag frei wählbar, Chefin bearbeitet auch
--  abgeschlossene Inventuren.
--  Setzt 20261011120000_lager_inventur.sql voraus.
--  Im Supabase SQL-Editor ausführen. Eine Transaktion, mehrfach ausführbar.
--
--    * Neue Inventur mit frei gewähltem Stichtag (alle Angemeldeten).
--    * Stichtag nachträglich ändern: nur die Chefin.
--    * Zählungen anlegen/ändern/löschen: in offener Inventur alle
--      Angemeldeten, in abgeschlossener nur die Chefin.
-- ════════════════════════════════════════════════════════════
BEGIN;

DO $pruef$
BEGIN
  IF to_regclass('public.lager_inventuren') IS NULL OR to_regclass('public.lager_inventur_zaehlungen') IS NULL THEN
    RAISE EXCEPTION 'Abbruch: zuerst 20261011120000_lager_inventur.sql ausführen.';
  END IF;
END $pruef$;

-- Alte Variante ohne Parameter ersetzen (sonst zwei gleichnamige Funktionen)
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

REVOKE ALL ON FUNCTION lager_inventur_starten(date), lager_inventur_stichtag_setzen(uuid, date) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION lager_inventur_starten(date), lager_inventur_stichtag_setzen(uuid, date) TO authenticated;

-- Zählungen: offene Inventur alle Angemeldeten, abgeschlossene nur Chefin
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

COMMIT;
