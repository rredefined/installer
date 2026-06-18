import axios from 'axios';
interface ModrinthGameVersion {
    version: string;
    version_type: string;
    date: string;
    major: boolean;
}
export const getMinecraftVersions = async (): Promise<string[]> => {
    try {
        const { data } = await axios.get<ModrinthGameVersion[]>('https://api.modrinth.com/v2/tag/game_version');
        return data
            .filter((v) => v.version_type === 'release')
            .map((v) => v.version)
            .sort((a, b) => {
                return b.localeCompare(a, undefined, { numeric: true, sensitivity: 'base' });
            });
    } catch (error) {
        console.error('Failed to fetch Minecraft versions:', error);
        return [];
    }
};
