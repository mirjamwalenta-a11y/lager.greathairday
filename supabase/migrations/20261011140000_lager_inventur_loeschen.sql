-- ════════════════════════════════════════════════════════════
--  LAGER · INVENTUR – Inventur löschen (nur Chefin)
--  Nur nötig, wenn 20261011120000_lager_inventur.sql in einer älteren
--  Fassung (ohne lager_inventur_loeschen) schon eingespielt wurde.
--  Eine Transaktion, mehrfach ausführbar.
-- ════════════════════════════════════════════════════════════
BEGIN;

DO $pruef$
BEGIN
  IF to_regclass('public.lager_inventuren') IS NULL THEN
    RAISE EXCEPTION 'Abbruch: zuerst 20261011120000_lager_inventur.sql ausführen.';
  END IF;
END $pruef$;

-- Inventur endgültig löschen (samt Zählungen): nur die Chefin
CREATE OR REPLACE FUNCTION lager_inventur_loeschen(p_id uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT abw_is_owner() THEN RAISE EXCEPTION 'Nur die Chefin'; END IF;
  DELETE FROM lager_inventur_zaehlungen WHERE inventur_id = p_id;
  DELETE FROM lager_inventuren WHERE id = p_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Inventur nicht gefunden'; END IF;
END $$;

REVOKE ALL ON FUNCTION lager_inventur_loeschen(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION lager_inventur_loeschen(uuid) TO authenticated;

COMMIT;
