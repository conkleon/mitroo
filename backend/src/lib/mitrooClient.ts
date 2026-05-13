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

export interface CreateMissionParams {
  title: string;
  start_date: string; // "YYYY-MM-DD"
  end_date: string;
  location_text?: string;
  location_url?: string;
  comments?: string;
  mission_type_id?: number; // default 16 (observed in HAR)
}

const MISSION_SUBMIT_VALUE = "ΔΗΜΙΟΥΡΓΙΑ";

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
    for (let skip = 0; ; skip += pageSize) {
      const res = await this._xhr(
        `/index.php/ajaxdptadmin/GridGetMissions/open/?$count=true&$skip=${skip}&$top=${pageSize}`,
      );
      const text = await res.text();
      try {
        const parsed = JSON.parse(text);
        const rows = Array.isArray(parsed) ? parsed : (parsed.result ?? []);
        all.push(...rows);
        if (rows.length < pageSize) break;
      } catch {
        console.error("[MitrooClient] fetchOpenMissions: failed to parse JSON response:", {
          skip,
          pageSize,
          snippet: text.slice(0, 300),
        });
        throw new Error("fetchOpenMissions: invalid JSON response");
      }
    }
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

  // ── Write-back ────────────────────────────────────────────────────────────

  async createMission(params: CreateMissionParams): Promise<number> {
    const beforeMissions = await this.fetchOpenMissions();
    const existingIds = new Set(beforeMissions.map((mission) => String(mission.id)));
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

    const title = params.title.trim();
    const startDate = params.start_date;
    const endDate = params.end_date;
    const missions = await this.fetchOpenMissions();
    const matches = missions.filter((mission) => {
      const missionTitle = String(mission.title ?? "").trim();
      if (!missionTitle || missionTitle !== title) return false;
      if (startDate && mission.start_date && mission.start_date !== startDate) return false;
      if (endDate && mission.end_date && mission.end_date !== endDate) return false;
      if (
        params.mission_type_id &&
        mission.mission_type_id &&
        Number(mission.mission_type_id) !== params.mission_type_id
      ) {
        return false;
      }
      if (params.location_text && mission.location_text && mission.location_text !== params.location_text) {
        return false;
      }
      return true;
    });

    const recentMatches = matches.filter((mission) => !existingIds.has(String(mission.id)));
    if (!recentMatches.length) {
      throw new Error(
        `createMission: no new mission found for "${params.title}" after create; check title, dates, and type`,
      );
    }
    const match = recentMatches.sort((a, b) => Number(b.id) - Number(a.id))[0];
    if (!match?.id) {
      throw new Error(`createMission: could not resolve mission ID for "${params.title}"`);
    }
    return Number(match.id);
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
