import { invoke } from './tauri';

export interface DiscordInfo {
  supported: boolean;
  status: string;
  label: string;
  enabled: boolean;
  appId: string;
  appName: string;
}

export const discordApi = {
  info: () => invoke<DiscordInfo>('discord_info'),
  setEnabled: (enabled: boolean) => invoke<void>('discord_set_enabled', { enabled }),
  reconnect: () => invoke<void>('discord_reconnect')
};
