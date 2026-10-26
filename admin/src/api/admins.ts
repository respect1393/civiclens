import { apiFetch } from './client';

export interface AdminAccount {
  id: string;
  name: string;
  email: string;
  role: string;
  state: string | null;
  district: string | null;
  createdAt: string;
}

interface BackendAdminAccount {
  id: string;
  name: string;
  email: string;
  role: string;
  state: string | null;
  district: string | null;
  createdAt: string;
}

interface BackendAdminListResponse {
  data: BackendAdminAccount[];
}

interface CreateAdminInput {
  name: string;
  email: string;
  password: string;
  state?: string | null;
  district?: string | null;
}

interface Invitation {
  id: string;
  token: string;
  email: string;
  expiresAt: string;
  usedAt: string | null;
}

interface CreateInvitationInput {
  email: string;
}

interface RegisterAdminInput {
  invitationToken: string;
  name: string;
  email: string;
  password: string;
  confirmPassword: string;
  state: string;
  district?: string | null;
}

function mapAdminAccount(raw: BackendAdminAccount): AdminAccount {
  return {
    id: raw.id,
    name: raw.name,
    email: raw.email,
    role: raw.role,
    state: raw.state,
    district: raw.district,
    createdAt: raw.createdAt,
  };
}

/** Fetches every administrator account visible to the current administrator. */
export async function fetchAdmins(signal?: AbortSignal): Promise<AdminAccount[]> {
  const response = await apiFetch<BackendAdminListResponse>('/admins', { signal });
  return (response.data ?? []).map(mapAdminAccount);
}

/** Creates a new administrator account (administrator-only endpoint). */
export async function createAdmin(input: CreateAdminInput): Promise<AdminAccount> {
  const body: Record<string, unknown> = {
    name: input.name,
    email: input.email,
    password: input.password,
  };
  if (input.state !== undefined && input.state !== null) {
    body.state = input.state;
  }
  if (input.district !== undefined && input.district !== null) {
    body.district = input.district;
  }

  const raw = await apiFetch<BackendAdminAccount>('/admins', {
    method: 'POST',
    body,
  });
  return mapAdminAccount(raw);
}

/** Issues a single-use administrator invitation (administrator-only endpoint). */
export async function createInvitation(input: CreateInvitationInput): Promise<Invitation> {
  const raw = await apiFetch<Invitation>('/invitations', {
    method: 'POST',
    body: { email: input.email },
  });
  return raw;
}

/** Creates an administrator account using a valid single-use invitation (public endpoint). */
export async function registerAdmin(input: RegisterAdminInput): Promise<AdminAccount> {
  const raw = await apiFetch<BackendAdminAccount>('/auth/register-admin', {
    method: 'POST',
    body: {
      invitationToken: input.invitationToken,
      name: input.name,
      email: input.email,
      password: input.password,
      confirmPassword: input.confirmPassword,
      state: input.state,
      district: input.district ?? null,
    },
  });
  return mapAdminAccount(raw);
}
