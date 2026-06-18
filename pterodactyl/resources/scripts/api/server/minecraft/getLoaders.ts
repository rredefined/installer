import axios from 'axios';
interface Loader {
    name: string;
    supported_project_types: string[];
}
export const getModrinthLoaders = async (type: 'plugin' | 'mod'): Promise<string[]> => {
    try {
        const { data } = await axios.get<Loader[]>('https://api.modrinth.com/v2/tag/loader');
        return data
            .filter((l) => l.supported_project_types.includes(type))
            .map((l) => l.name)
            .sort();
    } catch (error) {
        console.error('Failed to fetch Modrinth loaders:', error);
        return [];
    }
};
