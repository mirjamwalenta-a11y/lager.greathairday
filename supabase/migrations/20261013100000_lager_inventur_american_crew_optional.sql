-- ════════════════════════════════════════════════════════════
--  LAGER · INVENTUR – Firma American Crew; Barcode und Preis optional
--  Für Datenbanken, in die 20261011120000_lager_inventur.sql schon
--  eingespielt wurde. Eine Transaktion, mehrfach ausführbar.
--
--    * Produktfirma: zusätzlich „American Crew“ (inkl. Precision Blend,
--      Eksperience – buchhalterische Zuordnung laut Inventurliste 2026).
--    * Inventurposten ohne Barcode (gezählt per Liste/Suche) und noch ohne
--      Preis dürfen gezählt werden. Abschließen lässt die App erst, wenn
--      jeder gezählte Posten Bruttopreis und Stück pro Gebinde hat.
-- ════════════════════════════════════════════════════════════
BEGIN;

ALTER TABLE lager_inventur_zaehlungen
  DROP CONSTRAINT IF EXISTS lager_inventur_zaehlungen_produktfirma_check;
ALTER TABLE lager_inventur_zaehlungen
  ADD CONSTRAINT lager_inventur_zaehlungen_produktfirma_check
  CHECK (produktfirma IN ('Loreal', 'Nashi Argan', 'Goldwell', 'Wella', 'American Crew'));

ALTER TABLE lager_inventur_zaehlungen
  ALTER COLUMN barcode             DROP NOT NULL,
  ALTER COLUMN bruttopreis_gebinde DROP NOT NULL,
  ALTER COLUMN stueck_gebinde      DROP NOT NULL;

NOTIFY pgrst, 'reload schema';

COMMIT;
