// Client for the original Mitroo system (mitroo.redcross.gr).
// Uses cookie+CSRF session auth — no REST API, all server-side PHP/CodeIgniter.

export interface ExternalVolunteer {
  id: string | number;
  first_name: string;
  last_name: string;
  registration_code?: string;
  member_status?: string;
  rank_id?: string;
  member_department?: string;
  member_rank?: string;
  [key: string]: unknown;
}

export interface ExternalMission {
  id: number;
  title?: string;
  start_date?: string;
  end_date?: string;
  location_text?: string;
  mission_type_id?: string | number;
  [key: string]: unknown;
}

export interface ExternalShift {
  id: number | string;
  mission_id: number | string;
  shift_start_date?: string;
  shift_end_date?: string;
  total_participants?: number | string;
  title?: string;
  hours_lifeguard?: number | string;
  hours_sanitary?: number | string;
  hours_training?: number | string;
  hours_retraining?: number | string;
  hours_tep?: number | string;
  hours_volunteering?: number | string;
  [key: string]: unknown;
}

export interface ExternalShiftApplication {
  id: number | string;
  mission_id?: number | string;
  mission_shift_id?: number | string;
  member_id?: number | string;
  application_status_id?: number | string;
  hours_volunteering?: number | string;
  hours_sanitary?: number | string;
  hours_training?: number | string;
  hours_retraining?: number | string;
  hours_tep?: number | string;
  hours_lifeguard?: number | string;
  [key: string]: unknown;
}

export interface CreateMissionParams {
  title: string;
  start_date: string; // "YYYY-MM-DD"
  end_date: string;
  location_text?: string;
  location_url?: string;
  comments?: string;
  mission_type_id?: number; // default 16 (observed in HAR)
}

// Expected submit button value from the external Mitroo mission creation form.
const MISSION_SUBMIT_VALUE = "ΔΗΜΙΟΥΡΓΙΑ";

// Safety cap: prevent infinite pagination if the upstream API never returns a short page.
const MAX_OPEN_MISSION_PAGES = 200;
const MAX_SHIFT_APPLICATION_PAGES = 100;
const MAX_VOLUNTEER_PAGES = 200;
const EXTERNAL_DEBUG = process.env.MITROO_EXTERNAL_DEBUG === "1";

const debugExternal = (message: string, context?: Record<string, unknown>) => {
  if (!EXTERNAL_DEBUG) return;
  if (context) console.info(`[MitrooClient] ${message}`, context);
  else console.info(`[MitrooClient] ${message}`);
};

// Normalize external mission fields for matching between form inputs and API responses.
const normalizeDate = (value: string | undefined) =>
  value ? String(value).trim().slice(0, 10) : "";

const normalizeText = (value: string | undefined) =>
  value ? String(value).replace(/\s+/g, " ").trim() : "";

export interface CreateShiftParams {
  mission_id: number;
  shift_start_date: string; // "YYYY-MM-DD HH:mm"
  shift_end_date: string;
  total_participants?: number;
  comments?: string;
  hours_lifeguard?: number;
  hours_sanitary?: number;
  hours_training?: number;
  hours_retraining?: number;
  hours_tep?: number;
  hours_volunteering?: number;
  mission_type_id?: number; // default 16 (observed in HAR)
}

export class MitrooClient {
  private baseUrl: string;
  private cookies: Record<string, string> = {};
  private csrfToken = "";

  constructor(baseUrl: string) {
    this.baseUrl = baseUrl.replace(/\/$/, "");
  }

  // ── Auth ──────────────────────────────────────────────────────────────────

  async login(username: string, password: string): Promise<void> {
    // Step 1: GET login page to extract CSRF token
    const loginPageRes = await this._get("/index.php/auth/login");
    const loginHtml = await loginPageRes.text();
    const csrfMatch = loginHtml.match(/name="rccrmtk"\s+value="([^"]+)"/);
    if (!csrfMatch) throw new Error("Could not extract CSRF token from login page");
    this.csrfToken = csrfMatch[1];
    this._extractCookies(loginPageRes.headers);

    // Step 2: POST credentials
    const body = new URLSearchParams({
      identity: username,
      password,
      rccrmtk: this.csrfToken,
      remember: "1",
    });
    const loginRes = await this._post("/index.php/auth/login", body, { followRedirects: false });
    this._extractCookies(loginRes.headers);

    if (!this.cookies["rccrm_app_sessions"]) {
      throw new Error("Login failed: session cookie not set — check credentials");
    }
  }

  async forgotPassword(email: string): Promise<void> {
    // Step 1: GET forgot-password page to extract CSRF token + acquire session cookies
    const pageRes = await this._get("/index.php/auth/forgot_password");
    const html = await pageRes.text();
    this._extractCookies(pageRes.headers);
    const csrfMatch = html.match(/name="rccrmtk"\s+value="([^"]+)"/);
    const csrfToken = csrfMatch?.[1] ?? this.csrfToken;
    if (!csrfToken) throw new Error("Could not extract CSRF token from forgot-password page");

    // Step 2: POST the identity to trigger password reset email in original Mitroo
    const body = new URLSearchParams({
      identity: email,
      rccrmtk: csrfToken,
      submit: "Υποβολή",
    });
    const res = await this._post("/index.php/auth/forgot_password", body, { xhr: false });
    if (!res.ok) {
      const text = await res.text();
      throw new Error(`forgotPassword failed (${res.status}): ${text.slice(0, 200)}`);
    }
  }

  // ── Fetch helpers ─────────────────────────────────────────────────────────

  async fetchVolunteers(): Promise<ExternalVolunteer[]> {
    const res = await this._xhr("/index.php/ajaxmember/grid_get_volunteers");
    const text = await res.text();
    try {
      const parsed = JSON.parse(text);
      // Response is { count: "N", result: [...] }
      const rows = Array.isArray(parsed) ? parsed : (parsed.result ?? []);
      return rows;
    } catch {
      console.error("[MitrooClient] fetchVolunteers: unexpected response:", text.slice(0, 300));
      throw new Error("fetchVolunteers: invalid JSON response");
    }
  }

  async findVolunteerByEmail(email: string): Promise<ExternalVolunteer | null> {
    const normalized = email.trim().toLowerCase();
    const pageSize = 200;
    debugExternal("findVolunteerByEmail start", { email: normalized, pageSize });
    for (let page = 0; page < MAX_VOLUNTEER_PAGES; page += 1) {
      const skip = page * pageSize;
      const res = await this._xhr(
        `/index.php/ajaxmember/grid_get_volunteers/?$count=true&$skip=${skip}&$top=${pageSize}`,
      );
      const text = await res.text();
      try {
        const parsed = JSON.parse(text);
        const rows: ExternalVolunteer[] = Array.isArray(parsed)
          ? parsed
          : (parsed.result ?? []);
        const match = rows.find((vol) => {
          const candidate = typeof vol.email === "string" ? vol.email.trim().toLowerCase() : "";
          return candidate === normalized;
        });
        if (match) {
          debugExternal("findVolunteerByEmail match", { email: normalized, skip });
          return match;
        }
        if (rows.length < pageSize) {
          debugExternal("findVolunteerByEmail: exhausted pages without match", {
            email: normalized,
            totalPages: page + 1,
            sampleKeys: rows.length > 0 ? Object.keys(rows[0]).slice(0, 20) : [],
            sampleRow: rows.length > 0 ? JSON.stringify(rows[0]).slice(0, 300) : "empty",
          });
          return null;
        }
      } catch (error) {
        console.error("[MitrooClient] findVolunteerByEmail: invalid JSON response:", {
          skip,
          pageSize,
          snippet: text.slice(0, 300),
          error,
        });
        return null;
      }
    }
    console.warn("[MitrooClient] findVolunteerByEmail: reached pagination safety limit", {
      pageSize,
      maxPages: MAX_VOLUNTEER_PAGES,
    });
    return null;
  }

  async findVolunteerByCode(registrationCode: string): Promise<ExternalVolunteer | null> {
    const normalized = registrationCode.trim().toUpperCase();
    const pageSize = 200;
    for (let page = 0; page < MAX_VOLUNTEER_PAGES; page += 1) {
      const skip = page * pageSize;
      const res = await this._xhr(
        `/index.php/ajaxmember/grid_get_volunteers/?$count=true&$skip=${skip}&$top=${pageSize}`,
      );
      const text = await res.text();
      try {
        const parsed = JSON.parse(text);
        const rows: ExternalVolunteer[] = Array.isArray(parsed)
          ? parsed
          : (parsed.result ?? []);
        const match = rows.find((vol) => {
          const candidate =
            typeof vol.registration_code === "string"
              ? vol.registration_code.trim().toUpperCase()
              : "";
          return candidate === normalized;
        });
        if (match) return match;
        if (rows.length < pageSize) return null;
      } catch {
        console.error("[MitrooClient] findVolunteerByCode: invalid JSON response:", {
          skip,
          pageSize,
          snippet: text.slice(0, 300),
        });
        return null;
      }
    }
    console.warn("[MitrooClient] findVolunteerByCode: reached pagination safety limit", {
      pageSize,
      maxPages: MAX_VOLUNTEER_PAGES,
    });
    return null;
  }

  async fetchProfileIdentity(): Promise<{
    eame?: string;
    email?: string;
    forename?: string;
    surname?: string;
    phonePrimary?: string;
    phoneSecondary?: string;
    birthDate?: Date;
    address?: string;
    specializationNames?: string[];
  }> {
    const res = await this._get("/index.php/auth/profile");
    const html = await res.text();
    const emailMatch = html.match(/[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}/i);
    // Match eame: first char can be ASCII A-Z or Greek uppercase (Α-Ω, U+0391–U+03A9)
    const eameMatch = html.match(/[A-ZΑ-Ω]\d{5}\/\d{1,2}\/\d{2}/);
    const identity: {
      eame?: string;
      email?: string;
      forename?: string;
      surname?: string;
      phonePrimary?: string;
      phoneSecondary?: string;
      birthDate?: Date;
      address?: string;
      specializationNames?: string[];
    } = {};
    if (emailMatch?.[0]) identity.email = emailMatch[0].trim().toLowerCase();
    if (eameMatch?.[0]) identity.eame = eameMatch[0].trim();

    // Parse full name from sidebar username div (e.g. "ΧΡΙΣΤΟΠΟΥΛΟΣ ΚΩΝΣΤΑΝΤΙΝΟΣ ΚΛΕΩΝ")
    const nameMatch = html.match(/class="sidebar-username">([^<\[]+)/);
    if (nameMatch?.[1]) {
      const parts = nameMatch[1].trim().split(/\s+/);
      if (parts.length >= 2) {
        identity.surname = parts[0];
        identity.forename = parts.slice(1).join(" ");
      }
    }

    // Phone numbers: label "Τηλέφωνα (1ο | 2ο | Κινητό)", content "phone1 | phone2 | mobile"
    const phoneMatch = html.match(
      /class="collections-title">[^<]*Τηλέφωνα[^<]*<\/p>[\s\S]*?class="collections-content">([^<]*)<\/p>/,
    );
    if (phoneMatch?.[1]) {
      const parts = phoneMatch[1].split("|").map((p) => p.trim());
      const phone1 = parts[0] ?? "";
      const phone2 = parts[1] ?? "";
      const mobile = parts[2] ?? "";
      const primary = phone1 || phone2 || mobile;
      if (primary) identity.phonePrimary = primary;
      const secondary = [phone1, phone2, mobile].find((p) => p && p !== primary);
      if (secondary) identity.phoneSecondary = secondary;
    }

    // Birth date: "DD-MM-YYYY (age ετών)"
    const birthMatch = html.match(
      /class="collections-title">[^<]*Ημερομηνία γέννησης[^<]*<\/p>[\s\S]*?class="collections-content">([^<]*)<\/p>/,
    );
    if (birthMatch?.[1]) {
      const dateMatch = birthMatch[1].match(/(\d{2})-(\d{2})-(\d{4})/);
      if (dateMatch) {
        identity.birthDate = new Date(`${dateMatch[3]}-${dateMatch[2]}-${dateMatch[1]}T00:00:00Z`);
      }
    }

    // Address
    const addressMatch = html.match(
      /class="collections-title">[^<]*Διεύθυνση[^<]*<\/p>[\s\S]*?class="collections-content">([^<]*)<\/p>/,
    );
    if (addressMatch?.[1]) {
      const addr = addressMatch[1].trim();
      if (addr) identity.address = addr;
    }

    // Specializations: flex divs with text before &nbsp; in the "Επιπλέον Πληροφορίες" section
    const specializationNames: string[] = [];
    const flexDivRe =
      /<div[^>]*style="display:\s*flex;\s*align-items:\s*center;"[^>]*>\s*([\s\S]*?)&nbsp;/g;
    let flexMatch;
    while ((flexMatch = flexDivRe.exec(html)) !== null) {
      const raw = flexMatch[1].replace(/<[^>]+>/g, "").trim();
      if (raw && raw.length > 1) specializationNames.push(raw);
    }
    if (specializationNames.length > 0) identity.specializationNames = specializationNames;

    if (!identity.eame) {
      debugExternal("fetchProfileIdentity: eame not found", {
        hasEmail: Boolean(identity.email),
        snippet: html.slice(0, 500),
      });
    }
    return identity;
  }

  async testAdminAccess(): Promise<boolean> {
    try {
      const res = await this._xhr("/index.php/ajaxdptadmin/GridGetMissions");
      if (!res.ok) return false;
      const text = await res.text();
      JSON.parse(text); // admin returns JSON; non-admin gets an HTML redirect page
      return true;
    } catch {
      return false;
    }
  }

  async fetchMissions(): Promise<ExternalMission[]> {
    const res = await this._xhr("/index.php/ajaxdptadmin/GridGetMissions");
    const text = await res.text();
    try {
      const parsed = JSON.parse(text);
      const rows = Array.isArray(parsed) ? parsed : (parsed.result ?? []);
      return rows;
    } catch {
      console.error("[MitrooClient] fetchMissions: unexpected response:", text.slice(0, 300));
      throw new Error("fetchMissions: invalid JSON response");
    }
  }

  async fetchOpenMissions(): Promise<ExternalMission[]> {
    const pageSize = 200;
    const all: ExternalMission[] = [];
    for (let page = 0; page < MAX_OPEN_MISSION_PAGES; page += 1) {
      const skip = page * pageSize;
      const res = await this._xhr(
        `/index.php/ajaxdptadmin/GridGetMissions/open/?$count=true&$skip=${skip}&$top=${pageSize}`,
      );
      const text = await res.text();
      try {
        const parsed = JSON.parse(text);
        const rows = Array.isArray(parsed) ? parsed : (parsed.result ?? []);
        all.push(...rows);
        if (rows.length < pageSize) return all;
      } catch (error) {
        console.error("[MitrooClient] fetchOpenMissions: failed to parse JSON response:", {
          skip,
          pageSize,
          snippet: text.slice(0, 300),
          error,
        });
        throw new Error(`fetchOpenMissions: invalid JSON response (${error})`);
      }
    }
    console.warn("[MitrooClient] fetchOpenMissions: reached pagination safety limit", {
      pageSize,
      maxPages: MAX_OPEN_MISSION_PAGES,
      total: all.length,
    });
    return all;
  }

  async fetchShiftsForMission(missionId: number): Promise<ExternalShift[]> {
    const res = await this._xhr(
      `/index.php/ajaxdptadmin/mission_shifts_by_mission_with_members/${missionId}`,
    );
    const text = await res.text();
    try {
      const parsed = JSON.parse(text);
      // Response: { status: 1, mission_shifts: { count: N, data: [...] } }
      const rows = Array.isArray(parsed)
        ? parsed
        : (parsed.mission_shifts?.data ?? parsed.result ?? []);
      return rows;
    } catch {
      console.error("[MitrooClient] fetchShiftsForMission: unexpected response:", text.slice(0, 300));
      throw new Error("fetchShiftsForMission: invalid JSON response");
    }
  }

  async fetchShiftApplications(): Promise<ExternalShiftApplication[]> {
    const pageSize = 500;
    const all: ExternalShiftApplication[] = [];
    for (let page = 0; page < MAX_SHIFT_APPLICATION_PAGES; page += 1) {
      const skip = page * pageSize;
      const res = await this._xhr(
        `/index.php/ajaxdptadmin/grid_get_shiftapplications/?$count=true&$skip=${skip}&$top=${pageSize}`,
      );
      const text = await res.text();
      try {
        const parsed = JSON.parse(text);
        const rows: ExternalShiftApplication[] = Array.isArray(parsed)
          ? parsed
          : (parsed.result ?? []);
        all.push(...rows);
        if (rows.length < pageSize) return all;
      } catch (error) {
        console.error("[MitrooClient] fetchShiftApplications: failed to parse JSON response:", {
          skip,
          pageSize,
          snippet: text.slice(0, 300),
          error,
        });
        throw new Error(`fetchShiftApplications: invalid JSON response (${error})`);
      }
    }
    console.warn("[MitrooClient] fetchShiftApplications: reached pagination safety limit", {
      pageSize,
      maxPages: MAX_SHIFT_APPLICATION_PAGES,
      total: all.length,
    });
    return all;
  }

  // ── Write-back ────────────────────────────────────────────────────────────

  async createMission(params: CreateMissionParams): Promise<number> {
    // Fetch before/after snapshots to detect the newly created mission without an explicit ID response.
    // This intentionally performs two paginated reads because the external form does not return the new ID.
    const [beforeOpenMissions, beforeAllMissions] = await Promise.all([
      this.fetchOpenMissions(),
      this.fetchMissions(),
    ]);
    const existingOpenIds = new Set(beforeOpenMissions.map((mission) => String(mission.id)));
    const existingAllIds = new Set(beforeAllMissions.map((mission) => String(mission.id)));
    await this._refreshCsrf();
    const body = new URLSearchParams({
      title: params.title,
      start_date: params.start_date,
      end_date: params.end_date,
      location_text: params.location_text ?? "",
      location_url: params.location_url ?? "",
      comments: params.comments ?? "",
      mission_type_id: String(params.mission_type_id ?? 16),
      rccrmtk: this.csrfToken,
      submit: MISSION_SUBMIT_VALUE,
    });
    const res = await this._post("/index.php/dptadmin/newmission", body, { xhr: false });
    const text = await res.text();
    if (!res.ok) {
      throw new Error(`createMission failed (${res.status}): ${text.slice(0, 200)}`);
    }

    const refreshHeader = res.headers.get("Refresh") ?? "";
    const refreshMatch = refreshHeader.match(/mission\/(\d+)/i);
    if (refreshMatch) return Number(refreshMatch[1]);

    const textMatch = text.match(/mission\/(\d+)/i) ?? text.match(/mission_id"\s+value="(\d+)"/i);
    if (textMatch) return Number(textMatch[1]);

    const title = normalizeText(params.title);
    const startDate = normalizeDate(params.start_date);
    const endDate = normalizeDate(params.end_date);
    const expectedLocation = normalizeText(params.location_text);
    const matchesParams = (mission: ExternalMission) => {
      const missionTitle = normalizeText(mission.title as string | undefined);
      if (!missionTitle || missionTitle !== title) return false;
      const missionStart = normalizeDate(mission.start_date as string | undefined);
      const missionEnd = normalizeDate(mission.end_date as string | undefined);
      if (startDate && missionStart && missionStart !== startDate) return false;
      if (endDate && missionEnd && missionEnd !== endDate) return false;
      if (
        params.mission_type_id &&
        mission.mission_type_id &&
        Number(mission.mission_type_id) !== params.mission_type_id
      ) {
        return false;
      }
      const missionLocation = normalizeText(mission.location_text as string | undefined);
      if (expectedLocation && missionLocation && missionLocation !== expectedLocation) return false;
      return true;
    };

    // Some deployments take a moment to index the newly created mission.
    // Try a few times with increasing backoff before failing.
    const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));
    const maxAttempts = 6;
    for (let attempt = 0; attempt < maxAttempts; attempt += 1) {
      try {
        const openMissions = await this.fetchOpenMissions();
        const openMatches = openMissions.filter(matchesParams);
        const recentOpenMatches = openMatches.filter(
          (mission) => !existingOpenIds.has(String(mission.id)),
        );
        if (recentOpenMatches.length) {
          const match = recentOpenMatches.reduce((best, mission) =>
            Number(mission.id) > Number(best.id) ? mission : best,
          );
          return Number(match.id);
        }

        const allMissions = await this.fetchMissions();
        const allMatches = allMissions.filter(matchesParams);
        const recentAllMatches = allMatches.filter(
          (mission) => !existingAllIds.has(String(mission.id)),
        );
        if (recentAllMatches.length) {
          const match = recentAllMatches.reduce((best, mission) =>
            Number(mission.id) > Number(best.id) ? mission : best,
          );
          return Number(match.id);
        }
      } catch (err) {
        // fetch may fail transiently; retry below
        console.warn('[MitrooClient] createMission: transient fetch error', err);
      }

      // Exponential-ish backoff: 0.5s, 1s, 1.5s, ...
      const waitMs = 500 * (attempt + 1);
      // If this was the last attempt, break to try relaxed matching below
      if (attempt < maxAttempts - 1) await sleep(waitMs);
    }

    // Last resort: relaxed matching by title only (case-insensitive), prefer newest
    try {
      const allMissions = await this.fetchMissions();
      const titleLower = normalizeText(params.title).toLowerCase();
      const titleMatches = allMissions
        .filter((m) => normalizeText(m.title as string | undefined).toLowerCase() === titleLower)
        .filter((mission) => !existingAllIds.has(String(mission.id)));
      if (titleMatches.length) {
        const match = titleMatches.reduce((best, mission) =>
          Number(mission.id) > Number(best.id) ? mission : best,
        );
        console.warn(
          `[MitrooClient] createMission: relaxed title-only match for "${params.title}", mission ${match.id}`,
        );
        return Number(match.id);
      }
    } catch (err) {
      console.warn('[MitrooClient] createMission: relaxed matching fetch failed', err);
    }

    // Final fallback: choose the newest mission that wasn't present in the "before" snapshot.
    try {
      const allMissions = await this.fetchMissions();
      const newMissions = allMissions.filter((m) => !existingAllIds.has(String(m.id)));
      if (newMissions.length) {
        const match = newMissions.reduce((best, mission) =>
          Number(mission.id) > Number(best.id) ? mission : best,
        );
        console.warn(
          `[MitrooClient] createMission: fallback selected newest mission ${match.id} after create for "${params.title}"`,
        );
        return Number(match.id);
      }
    } catch (err) {
      console.warn('[MitrooClient] createMission: final-fallback fetch failed', err);
    }

    throw new Error(
      `createMission: could not confirm mission creation for "${params.title}" — verify it exists in Mitroo`,
    );
  }

  async createShift(params: CreateShiftParams): Promise<number> {
    await this._refreshCsrf();
    const body = new URLSearchParams({
      mission_id: String(params.mission_id),
      mission_type_id: String(params.mission_type_id ?? 16),
      shift_start_date: params.shift_start_date,
      shift_end_date: params.shift_end_date,
      admin_member_id: "0",
      total_participants: String(params.total_participants ?? 1),
      comments: params.comments ?? "",
      hours_lifeguard: String(params.hours_lifeguard ?? 0),
      hours_sanitary: String(params.hours_sanitary ?? 0),
      hours_training: String(params.hours_training ?? 0),
      hours_retraining: String(params.hours_retraining ?? 0),
      hours_tep: String(params.hours_tep ?? 0),
      hours_volunteering: String(params.hours_volunteering ?? 0),
      rccrmtk: this.csrfToken,
    });
    const res = await this._post("/ajaxdptadmin/MissionAddShift", body);
    const text = await res.text();
    try {
      const json = JSON.parse(text);
      const id = json.new_shift_id;
      if (!id) throw new Error(`createShift: no shift ID in response: ${text.slice(0, 200)}`);
      return Number(id);
    } catch (e) {
      throw new Error(`createShift failed: ${e}`);
    }
  }

  async cancelShift(params: {
    missionId: number;
    shiftId: number;
    emailMessage?: string;
  }): Promise<void> {
    await this._refreshCsrf();
    const body = new URLSearchParams({
      mission_id: String(params.missionId),
      shift_id: String(params.shiftId),
      email_message: params.emailMessage ?? "",
      rccrmtk: this.csrfToken,
    });
    const res = await this._post("/ajaxdptadmin/MissionCancelShift", body);
    const text = await res.text();
    if (!res.ok) {
      throw new Error(`cancelShift failed (${res.status}): ${text.slice(0, 200)}`);
    }
  }

  async cancelMission(missionId: number): Promise<void> {
    await this._refreshCsrf();
    const body = new URLSearchParams({
      mission_id: String(missionId),
      new_status_id: "7",
      rccrmtk: this.csrfToken,
    });
    const res = await this._post("/ajaxdptadmin/MissionCancel", body);
    const text = await res.text();
    if (!res.ok) {
      throw new Error(`cancelMission failed (${res.status}): ${text.slice(0, 200)}`);
    }
  }

  async changeMissionStatus(missionId: number, statusId: number): Promise<void> {
    await this._refreshCsrf();
    const body = new URLSearchParams({
      rccrmtk: this.csrfToken,
      mission_id: String(missionId),
      new_status_id: String(statusId),
    });
    const res = await this._post("/ajaxdptadmin/MissionChangeStatus", body);
    const text = await res.text();
    try {
      const json = JSON.parse(text);
      if (json.status !== 1) {
        throw new Error(`changeMissionStatus: server returned status ${json.status}`);
      }
    } catch (e) {
      if (!res.ok) {
        throw new Error(`changeMissionStatus failed (${res.status}): ${text.slice(0, 200)}`);
      }
      throw e;
    }
  }

  async findApplicationIdForMember(shiftId: number, memberId: number): Promise<number | null> {
    // grid_get_shiftapplications returns { count, result: [{ id, mission_shift_id, member_id, ... }] }
    // Fetch a generous page — departments rarely have more than a few hundred pending applications
    const res = await this._xhr(
      `/index.php/ajaxdptadmin/grid_get_shiftapplications/?$count=true&$skip=0&$top=500`,
    );
    const text = await res.text();
    try {
      const parsed = JSON.parse(text);
      const rows: Record<string, unknown>[] = Array.isArray(parsed)
        ? parsed
        : (parsed.result ?? []);
      const app = rows.find(
        (r) => Number(r.mission_shift_id) === shiftId && Number(r.member_id) === memberId,
      );
      return app ? Number(app.id) : null;
    } catch {
      console.error("[MitrooClient] findApplicationIdForMember: unexpected response:", text.slice(0, 300));
      return null;
    }
  }

  async updateApplicationHours(
    applicationId: number,
    missionId: number,
    hours: {
      volunteering?: number;
      sanitary?: number;
      training?: number;
      retraining?: number;
      tep?: number;
      lifeguard?: number;
    },
  ): Promise<void> {
    await this._refreshCsrf();
    const body = new URLSearchParams({
      rccrmtk: this.csrfToken,
      mission_id: String(missionId),
      shift_application_id: String(applicationId),
      popup_hours_volunteering: String(hours.volunteering ?? 0),
      popup_hours_sanitary: String(hours.sanitary ?? 0),
      popup_hours_training: String(hours.training ?? 0),
      popup_hours_retraining: String(hours.retraining ?? 0),
      popup_hours_tep: String(hours.tep ?? 0),
      popup_hours_lifeguard: String(hours.lifeguard ?? 0),
      also_change_application_status: "0",
    });
    const res = await this._post("/ajaxdptadmin/ShiftApplicationUpdateHours", body);
    const text = await res.text();
    try {
      const json = JSON.parse(text);
      if (!json.status) throw new Error(`updateApplicationHours: server returned status=false`);
    } catch (e) {
      if (!res.ok) throw new Error(`updateApplicationHours failed (${res.status}): ${text.slice(0, 200)}`);
    }
  }

  // Returns the new application ID, or null if the response doesn't include it.
  async addUserToShift(shiftId: number, memberId: number): Promise<number | null> {
    await this._refreshCsrf();
    const body = new URLSearchParams({
      rccrmtk: this.csrfToken,
      mission_shift_id: String(shiftId),
      mission_application_comments: "",
    });
    const res = await this._post(
      `/ajaxcommon/mission_shifts_application_add/0/1/${memberId}`,
      body,
    );
    const text = await res.text();
    try {
      const json = JSON.parse(text);
      if (json.status !== 1) {
        // status 0 often means the user already has an application for this shift
        const msg = (json.title as string) || String(json.status);
        throw new Error(`addUserToShift: ${msg} (status=${json.status})`);
      }
      return json.application_id ?? json.id ?? null;
    } catch (e) {
      throw new Error(`addUserToShift failed: ${e}`);
    }
  }

  async approveShiftApplication(applicationId: number): Promise<void> {
    const res = await this._xhr(
      `/ajaxdptadmin/ShiftApplicationStatusChange/${applicationId}/3`,
    );
    const text = await res.text();
    try {
      const json = JSON.parse(text);
      if (json.status !== 1) {
        throw new Error(`approveShiftApplication: server returned status ${json.status}`);
      }
    } catch (e) {
      if (!res.ok) {
        throw new Error(`approveShiftApplication failed (${res.status}): ${text.slice(0, 200)}`);
      }
    }
  }

  async markShiftApplicationParticipated(applicationId: number): Promise<void> {
    const res = await this._xhr(
      `/ajaxdptadmin/ShiftApplicationStatusChange/${applicationId}/6`,
    );
    const text = await res.text();
    try {
      const json = JSON.parse(text);
      if (json.status !== 1) {
        throw new Error(`markShiftApplicationParticipated: server returned status ${json.status}`);
      }
    } catch (e) {
      if (!res.ok) {
        throw new Error(`markShiftApplicationParticipated failed (${res.status}): ${text.slice(0, 200)}`);
      }
    }
  }

  async cancelShiftApplication(applicationId: number): Promise<void> {
    const res = await this._xhr(
      `/ajaxdptadmin/ShiftApplicationStatusChange/${applicationId}/4`,
    );
    const text = await res.text();
    try {
      const json = JSON.parse(text);
      if (json.status !== 1) {
        throw new Error(`cancelShiftApplication: server returned status ${json.status}`);
      }
    } catch (e) {
      if (!res.ok) {
        throw new Error(`cancelShiftApplication failed (${res.status}): ${text.slice(0, 200)}`);
      }
    }
  }

  async cancelMemberShiftApplication(applicationId: number): Promise<void> {
    await this._refreshCsrf();
    const body = new URLSearchParams({
      shift_application_id: String(applicationId),
      rccrmtk: this.csrfToken,
    });
    console.log(`[mitrooClient] cancelMemberShiftApplication: POST /ajaxcommon/member_shift_application_cancel body=${body.toString()}`);
    const res = await this._post("/ajaxcommon/member_shift_application_cancel", body);
    const text = await res.text();
    console.log(`[mitrooClient] cancelMemberShiftApplication: HTTP ${res.status} response body=${text.slice(0, 500)}`);
    try {
      const json = JSON.parse(text);
      if (json.status !== 1) {
        throw new Error(`cancelMemberShiftApplication: server returned status ${json.status}, title=${json.title ?? "N/A"}`);
      }
    } catch (e) {
      if (!res.ok) {
        throw new Error(`cancelMemberShiftApplication failed (${res.status}): ${text.slice(0, 200)}`);
      }
      throw e;
    }
  }

  // ── Private HTTP helpers ──────────────────────────────────────────────────

  private _cookieHeader(): string {
    return Object.entries(this.cookies)
      .map(([k, v]) => `${k}=${v}`)
      .join("; ");
  }

  private _extractCookies(headers: Headers): void {
    const raw = headers.getSetCookie?.() ?? [];
    for (const cookie of raw) {
      const [pair] = cookie.split(";");
      const eqIdx = pair.indexOf("=");
      if (eqIdx === -1) continue;
      const name = pair.slice(0, eqIdx).trim();
      const value = pair.slice(eqIdx + 1).trim();
      this.cookies[name] = value;
    }
  }

  private async _get(path: string): Promise<Response> {
    return fetch(`${this.baseUrl}${path}`, {
      headers: { Cookie: this._cookieHeader() },
      redirect: "follow",
    });
  }

  private async _xhr(path: string): Promise<Response> {
    return fetch(`${this.baseUrl}${path}`, {
      headers: {
        Cookie: this._cookieHeader(),
        "X-Requested-With": "XMLHttpRequest",
        Accept: "application/json, text/javascript, */*; q=0.01",
      },
    });
  }

  private async _post(
    path: string,
    body: URLSearchParams,
    opts: { followRedirects?: boolean; xhr?: boolean } = {},
  ): Promise<Response> {
    const headers: Record<string, string> = {
      Cookie: this._cookieHeader(),
      "Content-Type": "application/x-www-form-urlencoded; charset=UTF-8",
    };
    if (opts.xhr !== false) headers["X-Requested-With"] = "XMLHttpRequest";
    return fetch(`${this.baseUrl}${path}`, {
      method: "POST",
      headers,
      body: body.toString(),
      redirect: opts.followRedirects === false ? "manual" : "follow",
    });
  }

  private async _refreshCsrf(): Promise<void> {
    if (this.csrfToken) return;
    const res = await this._get("/index.php/auth/login");
    const html = await res.text();
    const match = html.match(/name="rccrmtk"\s+value="([^"]+)"/);
    if (match) this.csrfToken = match[1];
  }
}
