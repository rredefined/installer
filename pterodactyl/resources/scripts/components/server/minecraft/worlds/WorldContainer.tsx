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
import {
    getWorlds,
    getInstalledWorlds,
    deleteWorld,
    setActiveWorld,
    World,
    InstalledWorld,
} from '@/api/server/minecraft/worlds';
import WorldModal from '@/components/server/minecraft/worlds/WorldModal';
import { Dialog } from '@/components/elements/dialog';
export default () => {
    const { clearFlashes, clearAndAddHttpError, addFlash } = useFlash();
    const uuid = ServerContext.useStoreState((state) => state.server.data!.uuid);
    const [provider, setProvider] = useState('curseforge');
    const [pageSize, setPageSize] = useState(20);
    const [search, setSearch] = useState('');
    const [page, setPage] = useState(1);
    const [worlds, setWorlds] = useState<PaginatedResult<World> | null>(null);
    const [installedWorlds, setInstalledWorlds] = useState<InstalledWorld[]>([]);
    const [activeWorld, setActiveWorldName] = useState('');
    const [loading, setLoading] = useState(false);
    const [selectedWorld, setSelectedWorld] = useState<World | null>(null);
    const [worldToDelete, setWorldToDelete] = useState<string | null>(null);
    const searchWorlds = () => {
        setLoading(true);
        clearFlashes('worlds');
        getWorlds(uuid, {
            provider,
            page_size: pageSize,
            page,
            search_query: search,
        })
            .then((data) => {
                setWorlds({
                    items: data.data,
                    pagination: getPaginationSet(data.meta.pagination),
                });
            })
            .catch((error) => {
                clearAndAddHttpError({ key: 'worlds', error });
            })
            .finally(() => setLoading(false));
    };
    const loadInstalled = () => {
        getInstalledWorlds(uuid)
            .then(({ worlds, active_world }) => {
                setInstalledWorlds(worlds);
                setActiveWorldName(active_world);
            })
            .catch(console.error);
    };
    useEffect(() => {
        loadInstalled();
    }, []);
    const handleDeleteWorld = () => {
        if (!worldToDelete) return;
        clearFlashes('worlds');
        deleteWorld(uuid, worldToDelete)
            .then(() => {
                addFlash({ key: 'worlds', type: 'success', message: `World '${worldToDelete}' has been deleted.` });
                setWorldToDelete(null);
                loadInstalled();
            })
            .catch((error) => clearAndAddHttpError({ key: 'worlds', error }));
    };
    const handleSetActive = (name: string) => {
        clearFlashes('worlds');
        setActiveWorld(uuid, name)
            .then(() => {
                addFlash({ key: 'worlds', type: 'success', message: `World '${name}' is now the default world.` });
                loadInstalled();
            })
            .catch((error) => clearAndAddHttpError({ key: 'worlds', error }));
    };
    useEffect(() => {
        setPage(1);
    }, [provider, pageSize, search]);
    useEffect(() => {
        const delayDebounceFn = setTimeout(() => {
            searchWorlds();
        }, 500);
        return () => clearTimeout(delayDebounceFn);
    }, [page, provider, pageSize, search]);
    return (
        <ServerContentBlock title={'World Installer'}>
            <FlashMessageRender byKey={'worlds'} className={'mb-4'} />
            <div className={'flex flex-col md:flex-row gap-4 items-start'}>
                {/* Sidebar */}
                <div className={'w-full md:w-1/4 sticky top-4'}>
                    <div className={'bg-neutral-700 rounded p-4 shadow-md'}>
                        <div className={'mb-4'}>
                            <Label>Provider</Label>
                            <Select value={provider} onChange={(e) => setProvider(e.target.value)}>
                                <option value='curseforge'>CurseForge</option>
                            </Select>
                        </div>
                        <div className={'mb-4'}>
                            <Label>Page Size</Label>
                            <Select value={pageSize} onChange={(e) => setPageSize(Number(e.target.value))}>
                                <option value='10'>10</option>
                                <option value='20'>20</option>
                                <option value='50'>50</option>
                            </Select>
                        </div>
                        <div className={'mb-4'}>
                            <Label>Search</Label>
                            <Input
                                type={'text'}
                                value={search}
                                onChange={(e) => setSearch(e.target.value)}
                                placeholder={'Search worlds...'}
                            />
                        </div>
                        <div>
                            <Label>Installed Worlds</Label>
                            {installedWorlds.length === 0 ? (
                                <div className={'text-sm text-neutral-300 mt-1'}>No worlds detected</div>
                            ) : (
                                <div className={'mt-2 space-y-2 max-h-60 overflow-y-auto pr-2'}>
                                    {installedWorlds.map((world) => (
                                        <div
                                            key={world.name}
                                            className={`p-3 rounded border ${
                                                world.name === activeWorld
                                                    ? 'bg-neutral-600 border-green-500'
                                                    : 'bg-neutral-600 border-transparent'
                                            }`}
                                        >
                                            <div className={'flex items-center justify-between mb-2'}>
                                                <span
                                                    className={'text-sm font-bold text-neutral-100 truncate'}
                                                    title={world.name}
                                                >
                                                    {world.name}
                                                </span>
                                                {world.name === activeWorld && (
                                                    <span className={'text-xs text-green-400 font-semibold uppercase'}>
                                                        Active
                                                    </span>
                                                )}
                                            </div>
                                            <div className={'flex gap-2'}>
                                                {world.name !== activeWorld && (
                                                    <button
                                                        className={
                                                            'text-xs bg-neutral-500 hover:bg-neutral-400 text-neutral-100 px-2 py-1 rounded flex-1 transition-colors'
                                                        }
                                                        onClick={() => handleSetActive(world.name)}
                                                    >
                                                        Make Default
                                                    </button>
                                                )}
                                                <button
                                                    className={
                                                        'text-xs bg-red-600 hover:bg-red-500 text-white px-2 py-1 rounded flex-1 transition-colors'
                                                    }
                                                    onClick={() => setWorldToDelete(world.name)}
                                                >
                                                    Delete
                                                </button>
                                            </div>
                                        </div>
                                    ))}
                                </div>
                            )}
                        </div>
                    </div>
                </div>
                {/* Main Content */}
                <div className={'w-full md:w-3/4'}>
                    {!worlds || (loading && !worlds.items?.length) ? (
                        <div className={'w-full flex justify-center mt-8'}>
                            <Spinner size={'large'} />
                        </div>
                    ) : (
                        <Pagination data={worlds} onPageSelect={setPage}>
                            {({ items }) => (
                                <div className={'grid grid-cols-1 lg:grid-cols-2 gap-4'}>
                                    {items.map((world) => (
                                        <GreyRowBox
                                            key={world.id}
                                            className={
                                                'cursor-pointer hover:bg-neutral-600 transition-colors duration-150 flex flex-col h-full items-start p-4 border border-transparent hover:border-neutral-500'
                                            }
                                            onClick={() => setSelectedWorld(world)}
                                        >
                                            <div className={'flex items-center w-full'}>
                                                {world.icon_url ? (
                                                    <img
                                                        src={world.icon_url}
                                                        alt={world.name}
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
                                                        {world.name}
                                                    </p>
                                                    <p
                                                        className={'text-neutral-200 text-xs line-clamp-1 mt-auto'}
                                                        title={world.description}
                                                    >
                                                        {world.description || 'No description available.'}
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
                                            No worlds found matching your criteria.
                                        </div>
                                    )}
                                </div>
                            )}
                        </Pagination>
                    )}
                </div>
            </div>
            <WorldModal
                world={selectedWorld}
                provider={provider}
                onDismissed={() => setSelectedWorld(null)}
                onInstalled={() => {
                    setSelectedWorld(null);
                    loadInstalled();
                }}
            />
            <Dialog.Confirm
                open={!!worldToDelete}
                title={'Delete World'}
                confirm={'Delete'}
                onClose={() => setWorldToDelete(null)}
                onConfirmed={handleDeleteWorld}
            >
                Are you sure you want to delete the world directory <strong>{worldToDelete}</strong>? This action cannot
                be undone.
            </Dialog.Confirm>
        </ServerContentBlock>
    );
};
