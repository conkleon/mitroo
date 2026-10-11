/**
 * Global kill switch for all communication with the original Mitroo
 * (mitroo.redcross.gr): scheduled sync, manual sync, write-backs and
 * login/forgot-password proxying.
 *
 * Controlled by MITROO_SYNC_ENABLED. Defaults to enabled when unset;
 * "false", "0", "no" or "off" (case-insensitive) disable it.
 */
export function isMitrooSyncEnabled(): boolean {
  const raw = process.env.MITROO_SYNC_ENABLED?.trim().toLowerCase();
  if (!raw) return true;
  return !["false", "0", "no", "off"].includes(raw);
}

export class MitrooSyncDisabledError extends Error {
  constructor() {
    super("Mitroo sync is disabled (MITROO_SYNC_ENABLED=false)");
    this.name = "MitrooSyncDisabledError";
  }
}
