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
import { getModpacks, getRecentModpacks, Modpack, RecentModpack } from '@/api/server/minecraft/modpacks';
import ModpackModal from '@/components/server/minecraft/modpacks/ModpackModal';
export default () => {
    const { clearFlashes, clearAndAddHttpError } = useFlash();
    const uuid = ServerContext.useStoreState((state) => state.server.data!.uuid);
    const [provider, setProvider] = useState('feedthebeast');
    const [pageSize, setPageSize] = useState(20);
    const [search, setSearch] = useState('');
    const [page, setPage] = useState(1);
    const [modpacks, setModpacks] = useState<PaginatedResult<Modpack> | null>(null);
    const [recentModpacks, setRecentModpacks] = useState<RecentModpack[]>([]);
    const [loading, setLoading] = useState(false);
    const [selectedModpack, setSelectedModpack] = useState<Modpack | null>(null);
    const searchModpacks = () => {
        setLoading(true);
        clearFlashes('modpacks');
        getModpacks(uuid, {
            provider,
            page_size: pageSize,
            page,
            search_query: search,
        })
            .then((data) => {
                setModpacks({
                    items: data.data,
                    pagination: getPaginationSet(data.meta.pagination),
                });
            })
            .catch((error) => {
                clearAndAddHttpError({ key: 'modpacks', error });
            })
            .finally(() => setLoading(false));
    };
    const loadRecent = () => {
        getRecentModpacks(uuid).then(setRecentModpacks).catch(console.error);
    };
    useEffect(() => {
        loadRecent();
    }, []);
    useEffect(() => {
        setPage(1);
    }, [provider, pageSize, search]);
    useEffect(() => {
        const delayDebounceFn = setTimeout(() => {
            searchModpacks();
        }, 500);
        return () => clearTimeout(delayDebounceFn);
    }, [page, provider, pageSize, search]);
    return (
        <ServerContentBlock title={'Modpack Installer'}>
            <FlashMessageRender byKey={'modpacks'} className={'mb-4'} />
            <div className={'flex flex-col md:flex-row gap-4 items-start'}>
                {/* Sidebar */}
                <div className={'w-full md:w-1/4 sticky top-4'}>
                    <div className={'bg-neutral-700 rounded p-4 shadow-md'}>
                        <div className={'mb-4'}>
                            <Label>Provider</Label>
                            <Select value={provider} onChange={(e) => setProvider(e.target.value)}>
                                <option value='modrinth'>Modrinth</option>
                                <option value='curseforge'>CurseForge</option>
                                <option value='feedthebeast'>Feed The Beast</option>
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
                                placeholder={'Search modpacks...'}
                            />
                        </div>
                        <div>
                            <Label>Recently Installed</Label>
                            {recentModpacks.length === 0 ? (
                                <div className={'text-sm text-neutral-300 mt-1'}>No modpacks installed yet</div>
                            ) : (
                                <div className={'mt-2 space-y-2'}>
                                    {recentModpacks.slice(0, 5).map((pack) => (
                                        <div
                                            key={pack.id}
                                            className={
                                                'flex items-center p-2 rounded bg-neutral-600 hover:bg-neutral-500 cursor-pointer transition-colors'
                                            }
                                            onClick={() => {
                                                setProvider(pack.provider);
                                                setSelectedModpack({
                                                    id: pack.modpack_id,
                                                    name: pack.name,
                                                    description: 'Recently installed',
                                                    icon_url: pack.icon_url,
                                                });
                                            }}
                                        >
                                            {pack.icon_url ? (
                                                <img
                                                    src={pack.icon_url}
                                                    className={'w-8 h-8 rounded mr-2 bg-neutral-800 object-cover'}
                                                />
                                            ) : (
                                                <div
                                                    className={
                                                        'w-8 h-8 rounded mr-2 bg-neutral-500 flex items-center justify-center text-xs'
                                                    }
                                                >
                                                    IMG
                                                </div>
                                            )}
                                            <div className={'flex-1 min-w-0'}>
                                                <div className={'text-sm font-bold truncate text-neutral-100'}>
                                                    {pack.name}
                                                </div>
                                                <div className={'text-xs text-neutral-400 truncate'}>
                                                    {pack.provider}
                                                </div>
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
                    {!modpacks || (loading && !modpacks.items?.length) ? (
                        <div className={'w-full flex justify-center mt-8'}>
                            <Spinner size={'large'} />
                        </div>
                    ) : (
                        <Pagination data={modpacks} onPageSelect={setPage}>
                            {({ items }) => (
                                <div className={'grid grid-cols-1 lg:grid-cols-2 gap-4'}>
                                    {items.map((pack) => (
                                        <GreyRowBox
                                            key={pack.id}
                                            className={
                                                'cursor-pointer hover:bg-neutral-600 transition-colors duration-150 flex flex-col h-full items-start p-4 border border-transparent hover:border-neutral-500'
                                            }
                                            onClick={() => setSelectedModpack(pack)}
                                        >
                                            <div className={'flex items-center w-full'}>
                                                {pack.icon_url ? (
                                                    <img
                                                        src={pack.icon_url}
                                                        alt={pack.name}
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
                                                        {pack.name}
                                                    </p>
                                                    <p
                                                        className={'text-neutral-200 text-xs line-clamp-1 mt-auto'}
                                                        title={pack.description}
                                                    >
                                                        {pack.description || 'No description available.'}
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
                                            No modpacks found matching your criteria.
                                        </div>
                                    )}
                                </div>
                            )}
                        </Pagination>
                    )}
                </div>
            </div>
            <ModpackModal
                modpack={selectedModpack}
                provider={provider}
                onDismissed={() => setSelectedModpack(null)}
                onInstalled={() => {
                    setSelectedModpack(null);
                    loadRecent();
                }}
            />
        </ServerContentBlock>
    );
};
