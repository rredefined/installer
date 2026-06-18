import React, { useEffect, useState, useMemo } from 'react';
import { ServerContext } from '@/state/server';
import ServerContentBlock from '@/components/elements/ServerContentBlock';
import FlashMessageRender from '@/components/FlashMessageRender';
import useFlash from '@/plugins/useFlash';
import Select from '@/components/elements/Select';
import Input from '@/components/elements/Input';
import Spinner from '@/components/elements/Spinner';
import Label from '@/components/elements/Label';
import Button from '@/components/elements/Button';
import GreyRowBox from '@/components/elements/GreyRowBox';
import Pagination from '@/components/elements/Pagination';
import {
    getPacks,
    detectVersion,
    getWorlds,
    installPacks,
    VTCategory,
    VTPack,
    getPackImageUrl,
} from '@/api/server/minecraft/datapacks';
interface FlattenedPack extends VTPack {
    category: string;
}
export default () => {
    const { clearFlashes, clearAndAddHttpError, addFlash } = useFlash();
    const uuid = ServerContext.useStoreState((state) => state.server.data!.uuid);
    const [version, setVersion] = useState('1.21');
    const [type, setType] = useState('datapacks');
    const [world, setWorld] = useState('world');
    const [worlds, setWorlds] = useState<{ name: string }[]>([]);
    const [pageSize, setPageSize] = useState(20);
    const [page, setPage] = useState(1);
    const [categories, setCategories] = useState<VTCategory[]>([]);
    const [loading, setLoading] = useState(false);
    const [search, setSearch] = useState('');
    const [selectedPacks, setSelectedPacks] = useState<Record<string, string[]>>({});
    useEffect(() => {
        detectVersion(uuid).then((v) => {
            if (v) setVersion(v);
        });
        getWorlds(uuid).then((w) => {
            setWorlds(w);
            if (w.length > 0) setWorld(w[0].name);
        });
    }, []);
    useEffect(() => {
        setLoading(true);
        setCategories([]);
        setSelectedPacks({});
        getPacks(uuid, version, type)
            .then((data) => {
                if (Array.isArray(data)) {
                    setCategories(data as any);
                } else if (data && (data as any).categories) {
                    setCategories((data as any).categories);
                } else {
                    setCategories([]);
                }
            })
            .catch((error) => clearAndAddHttpError({ key: 'datapacks', error }))
            .finally(() => setLoading(false));
    }, [version, type]);
    useEffect(() => {
        setPage(1);
    }, [version, type, search, pageSize]);
    const togglePack = (category: string, pack: string) => {
        setSelectedPacks((prev) => {
            const current = prev[category] || [];
            if (current.includes(pack)) {
                return {
                    ...prev,
                    [category]: current.filter((p) => p !== pack),
                };
            } else {
                return {
                    ...prev,
                    [category]: [...current, pack],
                };
            }
        });
    };
    const allPacks = useMemo(() => {
        return categories.reduce((acc, cat) => {
            return acc.concat(cat.packs.map((p) => ({ ...p, category: cat.category })));
        }, [] as FlattenedPack[]);
    }, [categories]);
    const filteredPacks = useMemo(() => {
        if (!search) return allPacks;
        return allPacks.filter((p) => p.display.toLowerCase().includes(search.toLowerCase()));
    }, [allPacks, search]);
    const paginatedPacks = useMemo(() => {
        const start = (page - 1) * pageSize;
        const end = start + pageSize;
        return {
            items: filteredPacks.slice(start, end),
            pagination: {
                total: filteredPacks.length,
                count: Math.min(pageSize, filteredPacks.length - start),
                perPage: pageSize,
                currentPage: page,
                totalPages: Math.ceil(filteredPacks.length / pageSize),
            },
        };
    }, [filteredPacks, page, pageSize]);
    const selectedCount = Object.values(selectedPacks).reduce((acc, curr) => acc + curr.length, 0);
    const install = () => {
        const packsToInstall: Record<string, string[]> = {};
        Object.keys(selectedPacks).forEach((key) => {
            if (selectedPacks[key].length > 0) {
                packsToInstall[key] = selectedPacks[key];
            }
        });
        if (Object.keys(packsToInstall).length === 0) return;
        clearFlashes('datapacks');
        setLoading(true);
        installPacks(uuid, {
            version,
            type,
            packs: packsToInstall,
            world: type === 'datapacks' || type === 'craftingtweaks' ? world : undefined,
        })
            .then(() => {
                addFlash({
                    key: 'datapacks',
                    type: 'success',
                    message: 'Selected packs have been installed successfully.',
                });
                setSelectedPacks({});
            })
            .catch((error) => clearAndAddHttpError({ key: 'datapacks', error }))
            .finally(() => setLoading(false));
    };
    return (
        <ServerContentBlock title={'Datapack Installer'}>
            <FlashMessageRender byKey={'datapacks'} className={'mb-4'} />
            <div className={'flex flex-col md:flex-row gap-4 items-start'}>
                {/* Sidebar */}
                <div className={'w-full md:w-1/4 sticky top-4'}>
                    <div className={'bg-neutral-700 rounded p-4 shadow-md'}>
                        <div className={'mb-4'}>
                            <Label>Type</Label>
                            <Select value={type} onChange={(e) => setType(e.target.value)}>
                                <option value='datapacks'>Datapacks</option>
                                <option value='resourcepacks'>Resource Packs</option>
                                <option value='craftingtweaks'>Crafting Tweaks</option>
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
                            <Label>Minecraft Version</Label>
                            <Select value={version} onChange={(e) => setVersion(e.target.value)}>
                                <option value='1.21'>1.21</option>
                                <option value='1.20'>1.20</option>
                                <option value='1.19'>1.19</option>
                                <option value='1.18'>1.18</option>
                                <option value='1.17'>1.17</option>
                                <option value='1.16'>1.16</option>
                                <option value='1.15'>1.15</option>
                                <option value='1.14'>1.14</option>
                                <option value='1.13'>1.13</option>
                                <option value='1.13'>1.12</option>
                                <option value='1.13'>1.11</option>
                            </Select>
                        </div>
                        {(type === 'datapacks' || type === 'craftingtweaks') && (
                            <div className={'mb-4'}>
                                <Label>World</Label>
                                <Select value={world} onChange={(e) => setWorld(e.target.value)}>
                                    {worlds.map((w) => (
                                        <option key={w.name} value={w.name}>
                                            {w.name}
                                        </option>
                                    ))}
                                    {worlds.length === 0 && <option value='world'>world</option>}
                                </Select>
                            </div>
                        )}
                        <div className={'mb-4'}>
                            <Label>Search</Label>
                            <Input
                                type={'text'}
                                value={search}
                                onChange={(e) => setSearch(e.target.value)}
                                placeholder={'Search packs...'}
                            />
                        </div>
                        <div className={'mt-6'}>
                            <Button className={'w-full'} disabled={selectedCount === 0 || loading} onClick={install}>
                                Install {selectedCount} Packs
                            </Button>
                        </div>
                    </div>
                </div>
                {/* Main Content */}
                <div className={'w-full md:w-3/4'}>
                    {loading && allPacks.length === 0 ? (
                        <div className={'w-full flex justify-center mt-8'}>
                            <Spinner size={'large'} />
                        </div>
                    ) : (
                        <Pagination data={paginatedPacks} onPageSelect={setPage}>
                            {({ items }) => (
                                <div className={'grid grid-cols-1 lg:grid-cols-2 gap-4'}>
                                    {items.map((pack) => {
                                        const isSelected = (selectedPacks[pack.category] || []).includes(pack.name);
                                        return (
                                            <GreyRowBox
                                                key={pack.name}
                                                className={`cursor-pointer transition-colors duration-150 flex flex-col h-full items-start p-4 border ${
                                                    isSelected
                                                        ? '!border-green-500 bg-neutral-600'
                                                        : 'border-transparent hover:bg-neutral-600 hover:border-neutral-500'
                                                }`}
                                                onClick={() => togglePack(pack.category, pack.name)}
                                            >
                                                <div className={'flex items-center w-full'}>
                                                    <div className={'relative flex-shrink-0'}>
                                                        <img
                                                            src={getPackImageUrl(uuid, version, type, pack.name)}
                                                            alt={pack.display}
                                                            className={
                                                                'w-12 h-12 rounded mr-3 object-contain bg-neutral-800'
                                                            }
                                                            onError={(e) => {
                                                                e.currentTarget.src =
                                                                    'data:image/svg+xml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHZpZXdCb3g9IjAgMCAyNCAyNCI+PC9zdmc+';
                                                            }}
                                                        />
                                                    </div>
                                                    <div className={'flex-1 min-w-0'}>
                                                        <p className={'text-base text-neutral-100 line-clamp-1'}>
                                                            {pack.display}
                                                        </p>
                                                        <p
                                                            className={'text-neutral-200 text-xs line-clamp-1 mt-auto'}
                                                            title={pack.description}
                                                        >
                                                            {pack.description}
                                                        </p>
                                                    </div>
                                                </div>
                                            </GreyRowBox>
                                        );
                                    })}
                                    {items.length === 0 && !loading && (
                                        <div
                                            className={
                                                'col-span-3 text-center text-neutral-400 p-8 bg-neutral-700/50 rounded border-2 border-dashed border-neutral-600'
                                            }
                                        >
                                            No packs found matching your criteria.
                                        </div>
                                    )}
                                </div>
                            )}
                        </Pagination>
                    )}
                </div>
            </div>
        </ServerContentBlock>
    );
};
