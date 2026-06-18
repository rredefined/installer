import React, { useEffect, useState } from 'react';
import { ServerContext } from '@/state/server';
import ServerContentBlock from '@/components/elements/ServerContentBlock';
import FlashMessageRender from '@/components/FlashMessageRender';
import useFlash from '@/plugins/useFlash';
import Select from '@/components/elements/Select';
import Input from '@/components/elements/Input';
import Spinner from '@/components/elements/Spinner';
import Label from '@/components/elements/Label';
import GreyRowBox from '@/components/elements/GreyRowBox';
import Pagination from '@/components/elements/Pagination';
import { PaginatedResult, getPaginationSet } from '@/api/http';
import PluginModal from '@/components/server/minecraft/plugins/PluginModal';
import { getPlugins, Plugin } from '@/api/server/minecraft/plugins';
import { getMinecraftVersions } from '@/api/server/minecraft/getVersions';
import { getModrinthLoaders } from '@/api/server/minecraft/getLoaders';
export default () => {
    const { clearFlashes, clearAndAddHttpError } = useFlash();
    const uuid = ServerContext.useStoreState((state) => state.server.data!.uuid);
    const [provider, setProvider] = useState('modrinth');
    const [pageSize, setPageSize] = useState(20);
    const [search, setSearch] = useState('');
    const [page, setPage] = useState(1);
    const [plugins, setPlugins] = useState<PaginatedResult<Plugin> | null>(null);
    const [loading, setLoading] = useState(false);
    const [selectedPlugin, setSelectedPlugin] = useState<Plugin | null>(null);
    const [versions, setVersions] = useState<string[]>([]);
    const [version, setVersion] = useState('');
    const [loaders, setLoaders] = useState<string[]>([]);
    const [loader, setLoader] = useState('');
    useEffect(() => {
        getMinecraftVersions().then(setVersions);
    }, []);
    useEffect(() => {
        if (provider === 'modrinth') {
            getModrinthLoaders('plugin').then(setLoaders);
        } else {
            setLoaders([]);
            setLoader('');
        }
    }, [provider]);
    const searchPlugins = () => {
        setLoading(true);
        clearFlashes('plugins');
        getPlugins(uuid, {
            provider,
            page_size: pageSize,
            page,
            search_query: search,
            minecraft_version: version,
            loader,
        })
            .then((data) => {
                setPlugins({
                    items: data.data,
                    pagination: getPaginationSet(data.meta.pagination),
                });
            })
            .catch((error) => {
                clearAndAddHttpError({ key: 'plugins', error });
            })
            .finally(() => setLoading(false));
    };
    useEffect(() => {
        setPage(1);
    }, [provider, pageSize, search, version, loader]);
    useEffect(() => {
        const delayDebounceFn = setTimeout(() => {
            searchPlugins();
        }, 500);
        return () => clearTimeout(delayDebounceFn);
    }, [page, provider, pageSize, search, version, loader]);
    return (
        <ServerContentBlock title={'Plugin Installer'}>
            <FlashMessageRender byKey={'plugins'} className={'mb-4'} />
            <div className={'flex flex-col md:flex-row gap-4 items-start'}>
                {/* Sidebar */}
                <div className={'w-full md:w-1/4 sticky top-4'}>
                    <div className={'bg-neutral-700 rounded p-4 shadow-md'}>
                        <div className={'mb-4'}>
                            <Label>Provider</Label>
                            <Select value={provider} onChange={(e) => setProvider(e.target.value)}>
                                <option value='modrinth'>Modrinth</option>
                                <option value='curseforge'>CurseForge</option>
                                <option value='spigotmc'>SpigotMC</option>
                                <option value='hangar'>Hangar</option>
                            </Select>
                        </div>
                        <div className={'mb-4'}>
                            <Label>Minecraft Version</Label>
                            <Select value={version} onChange={(e) => setVersion(e.target.value)}>
                                <option value=''>All Versions</option>
                                {versions.map((v) => (
                                    <option key={v} value={v}>
                                        {v}
                                    </option>
                                ))}
                            </Select>
                        </div>
                        {provider === 'modrinth' && (
                            <div className={'mb-4'}>
                                <Label>Plugin Loader</Label>
                                <Select value={loader} onChange={(e) => setLoader(e.target.value)}>
                                    <option value=''>All Loaders</option>
                                    {loaders.map((l) => (
                                        <option key={l} value={l}>
                                            {l.charAt(0).toUpperCase() + l.slice(1)}
                                        </option>
                                    ))}
                                </Select>
                            </div>
                        )}
                        <div className={'mb-4'}>
                            <Label>Page Size</Label>
                            <Select value={pageSize} onChange={(e) => setPageSize(Number(e.target.value))}>
                                <option value='10'>10</option>
                                <option value='20'>20</option>
                                <option value='50'>50</option>
                            </Select>
                        </div>
                        <div>
                            <Label>Search</Label>
                            <Input
                                type={'text'}
                                value={search}
                                onChange={(e) => setSearch(e.target.value)}
                                placeholder={'Search plugins...'}
                            />
                        </div>
                    </div>
                </div>
                {/* Main Content */}
                <div className={'w-full md:w-3/4'}>
                    {!plugins || (loading && !plugins.items?.length) ? (
                        <div className={'w-full flex justify-center mt-8'}>
                            <Spinner size={'large'} />
                        </div>
                    ) : (
                        <Pagination data={plugins} onPageSelect={setPage}>
                            {({ items }) => (
                                <div className={'grid grid-cols-1 lg:grid-cols-2 gap-4'}>
                                    {items.map((plugin) => (
                                        <GreyRowBox
                                            key={plugin.id}
                                            className={
                                                'cursor-pointer hover:bg-neutral-600 transition-colors duration-150 flex flex-col h-full items-start p-4 border border-transparent hover:border-neutral-500'
                                            }
                                            onClick={() => setSelectedPlugin(plugin)}
                                        >
                                            <div className={'flex items-center w-full'}>
                                                {plugin.icon_url ? (
                                                    <img
                                                        src={plugin.icon_url}
                                                        alt={plugin.name}
                                                        className={
                                                            'w-12 h-12 rounded mr-3 object-cover bg-neutral-800 flex-shrink-0'
                                                        }
                                                    />
                                                ) : (
                                                    <div
                                                        className={
                                                            'w-12 h-12 rounded mr-3 bg-neutral-600 flex items-center justify-center text-neutral-400 font-bold text-xs flex-shrink-0'
                                                        }
                                                    >
                                                        IMG
                                                    </div>
                                                )}
                                                <div className={'flex-1 min-w-0'}>
                                                    <p className={'text-base text-neutral-100 line-clamp-1'}>
                                                        {plugin.name}
                                                    </p>
                                                    <p
                                                        className={'text-neutral-200 text-xs line-clamp-1 mt-auto'}
                                                        title={plugin.description}
                                                    >
                                                        {plugin.description || 'No description available.'}
                                                    </p>
                                                </div>
                                            </div>
                                        </GreyRowBox>
                                    ))}
                                    {items.length === 0 && (
                                        <div
                                            className={
                                                'col-span-3 text-center text-neutral-400 p-8 bg-neutral-700/50 rounded border-2 border-dashed border-neutral-600'
                                            }
                                        >
                                            No plugins found matching your criteria.
                                        </div>
                                    )}
                                </div>
                            )}
                        </Pagination>
                    )}
                </div>
            </div>
            <PluginModal
                plugin={selectedPlugin}
                provider={provider}
                onDismissed={() => setSelectedPlugin(null)}
                onInstalled={() => {
                    setSelectedPlugin(null);
                }}
            />
        </ServerContentBlock>
    );
};
