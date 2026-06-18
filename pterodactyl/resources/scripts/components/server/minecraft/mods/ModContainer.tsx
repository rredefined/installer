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
import ModModal from '@/components/server/minecraft/mods/ModModal';
import { getMods, Mod } from '@/api/server/minecraft/mods';
import { getMinecraftVersions } from '@/api/server/minecraft/getVersions';
import { getModrinthLoaders } from '@/api/server/minecraft/getLoaders';
export default () => {
    const { clearFlashes, clearAndAddHttpError } = useFlash();
    const uuid = ServerContext.useStoreState((state) => state.server.data!.uuid);
    const [provider, setProvider] = useState('modrinth');
    const [pageSize, setPageSize] = useState(20);
    const [search, setSearch] = useState('');
    const [page, setPage] = useState(1);
    const [mods, setMods] = useState<PaginatedResult<Mod> | null>(null);
    const [loading, setLoading] = useState(false);
    const [selectedMod, setSelectedMod] = useState<Mod | null>(null);
    const [versions, setVersions] = useState<string[]>([]);
    const [version, setVersion] = useState('');
    const [loaders, setLoaders] = useState<string[]>([]);
    const [loader, setLoader] = useState('');
    useEffect(() => {
        getMinecraftVersions().then(setVersions);
    }, []);
    useEffect(() => {
        if (provider === 'modrinth') {
            getModrinthLoaders('mod').then(setLoaders);
        } else {
            setLoaders([]);
            setLoader('');
        }
    }, [provider]);
    const searchMods = () => {
        setLoading(true);
        clearFlashes('mods');
        getMods(uuid, {
            provider,
            page_size: pageSize,
            page,
            search_query: search,
            minecraft_version: version,
            loader,
        })
            .then((data) => {
                setMods({
                    items: data.data,
                    pagination: getPaginationSet(data.meta.pagination),
                });
            })
            .catch((error) => {
                clearAndAddHttpError({ key: 'mods', error });
            })
            .finally(() => setLoading(false));
    };
    useEffect(() => {
        setPage(1);
    }, [provider, pageSize, search, version, loader]);
    useEffect(() => {
        const delayDebounceFn = setTimeout(() => {
            searchMods();
        }, 500);
        return () => clearTimeout(delayDebounceFn);
    }, [page, provider, pageSize, search, version, loader]);
    return (
        <ServerContentBlock title={'Mod Installer'}>
            <FlashMessageRender byKey={'mods'} className={'mb-4'} />
            <div className={'flex flex-col md:flex-row gap-4 items-start'}>
                {/* Sidebar */}
                <div className={'w-full md:w-1/4 sticky top-4'}>
                    <div className={'bg-neutral-700 rounded p-4 shadow-md'}>
                        <div className={'mb-4'}>
                            <Label>Provider</Label>
                            <Select value={provider} onChange={(e) => setProvider(e.target.value)}>
                                <option value='modrinth'>Modrinth</option>
                                <option value='curseforge'>CurseForge</option>
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
                                <Label>Mod Loader</Label>
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
                                placeholder={'Search mods...'}
                            />
                        </div>
                    </div>
                </div>
                {/* Main Content */}
                <div className={'w-full md:w-3/4'}>
                    {!mods || (loading && !mods.items?.length) ? (
                        <div className={'w-full flex justify-center mt-8'}>
                            <Spinner size={'large'} />
                        </div>
                    ) : (
                        <Pagination data={mods} onPageSelect={setPage}>
                            {({ items }) => (
                                <div className={'grid grid-cols-1 lg:grid-cols-2 gap-4'}>
                                    {items.map((mod) => (
                                        <GreyRowBox
                                            key={mod.id}
                                            className={
                                                'cursor-pointer hover:bg-neutral-600 transition-colors duration-150 flex flex-col h-full items-start p-4 border border-transparent hover:border-neutral-500'
                                            }
                                            onClick={() => setSelectedMod(mod)}
                                        >
                                            <div className={'flex items-center w-full'}>
                                                {mod.icon_url ? (
                                                    <img
                                                        src={mod.icon_url}
                                                        alt={mod.name}
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
                                                        {mod.name}
                                                    </p>
                                                    <p
                                                        className={'text-neutral-200 text-xs line-clamp-1 mt-auto'}
                                                        title={mod.description}
                                                    >
                                                        {mod.description || 'No description available.'}
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
                                            No mods found matching your criteria.
                                        </div>
                                    )}
                                </div>
                            )}
                        </Pagination>
                    )}
                </div>
            </div>
            <ModModal
                mod={selectedMod}
                provider={provider}
                onDismissed={() => setSelectedMod(null)}
                onInstalled={() => {
                    setSelectedMod(null);
                }}
            />
        </ServerContentBlock>
    );
};
