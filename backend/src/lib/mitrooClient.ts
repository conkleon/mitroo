// Client for the original Mitroo system (mitroo.redcross.gr).
// Uses cookie+CSRF session auth — no REST API, all server-side PHP/CodeIgniter.

export interface ExternalVolunteer {
  member_id: number;
  email: string;
  firstname: string;
  lastname: string;
  mobile?: string;
  phone?: string;
  address?: string;
  [key: string]: unknown; // allow unknown fields — log on first run to confirm mapping
}

export interface ExternalMission {
  mission_id: number;
  name?: string;
  title?: string;
  start_date?: string;
  end_date?: string;
  [key: string]: unknown;
}

export interface ExternalShift {
  shift_id: number;
  mission_id: number;
  shift_start_date?: string;
  shift_end_date?: string;
  total_participants?: number;
  name?: string;
  title?: string;
  [key: string]: unknown;
}

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
      return JSON.parse(text);
    } catch {
      console.error("[MitrooClient] fetchVolunteers: unexpected response:", text.slice(0, 300));
      throw new Error("fetchVolunteers: invalid JSON response");
    }
  }

  async fetchMissions(): Promise<ExternalMission[]> {
    const res = await this._xhr("/index.php/ajaxdptadmin/GridGetMissions");
    const text = await res.text();
    try {
      return JSON.parse(text);
    } catch {
      console.error("[MitrooClient] fetchMissions: unexpected response:", text.slice(0, 300));
      throw new Error("fetchMissions: invalid JSON response");
    }
  }

  async fetchShiftsForMission(missionId: number): Promise<ExternalShift[]> {
    const res = await this._xhr(
      `/ajaxdptadmin/mission_shifts_by_mission_with_members?mission_id=${missionId}`,
    );
    const text = await res.text();
    try {
      return JSON.parse(text);
    } catch {
      console.error("[MitrooClient] fetchShiftsForMission: unexpected response:", text.slice(0, 300));
      throw new Error("fetchShiftsForMission: invalid JSON response");
    }
  }

  // ── Write-back ────────────────────────────────────────────────────────────

  // ⚠️ HAR GAP: "create mission" endpoint not captured.
  // Discover by recording a HAR while creating a mission in the original Mitroo admin panel.
  // Expected path: /ajaxdptadmin/MissionCreate or similar.
  async createMission(name: string, startDate: string, endDate: string): Promise<number> {
    await this._refreshCsrf();
    const body = new URLSearchParams({
      name,
      start_date: startDate,
      end_date: endDate,
      rccrmtk: this.csrfToken,
    });
    // TODO: replace path once discovered from HAR recording
    const res = await this._post("/ajaxdptadmin/MissionCreate", body);
    const text = await res.text();
    try {
      const json = JSON.parse(text);
      const id = json.new_mission_id ?? json.mission_id ?? json.id;
      if (!id) throw new Error(`createMission: no ID in response: ${text.slice(0, 200)}`);
      return Number(id);
    } catch (e) {
      throw new Error(`createMission failed: ${e}`);
    }
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

  // ⚠️ HAR GAP: confirm exact POST body format for approval.
  // The status value and field names must be verified from a live HAR recording.
  async approveShiftApplication(applicationId: number): Promise<void> {
    await this._refreshCsrf();
    const body = new URLSearchParams({
      status: "2", // assumed "approved" status value — verify from HAR
      rccrmtk: this.csrfToken,
    });
    const res = await this._post(
      `/index.php/dptadmin/ShiftApplicationStatusChange/${applicationId}`,
      body,
    );
    if (!res.ok) {
      const text = await res.text();
      throw new Error(`approveShiftApplication failed (${res.status}): ${text.slice(0, 200)}`);
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
    opts: { followRedirects?: boolean } = {},
  ): Promise<Response> {
    return fetch(`${this.baseUrl}${path}`, {
      method: "POST",
      headers: {
        Cookie: this._cookieHeader(),
        "Content-Type": "application/x-www-form-urlencoded; charset=UTF-8",
        "X-Requested-With": "XMLHttpRequest",
      },
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
