-- ════════════════════════════════════════════════════════════
--  LAGER · INVENTUR – Produktgruppe Inventur in den Zählungen
--  Für Datenbanken, in die 20261011120000_lager_inventur.sql schon
--  eingespielt wurde. Eine Transaktion, mehrfach ausführbar.
--  Sammelzeilen in Auswertung/CSV: gleiche Firma + gleiche Produktgruppe
--  + gleicher Bruttopreis pro Stück (gerechnet wird in der App).
-- ════════════════════════════════════════════════════════════
BEGIN;

ALTER TABLE lager_inventur_zaehlungen
  ADD COLUMN IF NOT EXISTS produktgruppe text CHECK (char_length(produktgruppe) <= 80);

NOTIFY pgrst, 'reload schema';

COMMIT;
