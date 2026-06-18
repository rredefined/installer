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
import { PaginatedResult } from '@/api/http';
import {
    getMinecraftForks,
    getVersions,
    getCurrentVersion,
    ForkInfo,
    VersionInfo,
} from '@/api/server/minecraft/versions';
import VersionModal from '@/components/server/minecraft/versions/VersionModal';
interface VersionItem extends VersionInfo {
    id: string;
}
export default () => {
    const { clearFlashes, clearAndAddHttpError } = useFlash();
    const uuid = ServerContext.useStoreState((state) => state.server.data!.uuid);
    const [forks, setForks] = useState<Record<string, ForkInfo>>({});
    const [provider, setProvider] = useState('sponge');
    const [pageSize, setPageSize] = useState(20);
    const [search, setSearch] = useState('');
    const [filterType, setFilterType] = useState('all');
    const [page, setPage] = useState(1);
    const [versions, setVersions] = useState<PaginatedResult<VersionItem> | null>(null);
    const [currentVersion, setCurrentVersion] = useState<{ type: string; version: string; build: string } | null>(null);
    const [loading, setLoading] = useState(false);
    const [loadingForks, setLoadingForks] = useState(true);
    const [selectedVersion, setSelectedVersion] = useState<string | null>(null);
    const [forkSelectOpen, setForkSelectOpen] = useState(false);
    const [forkSearch, setForkSearch] = useState('');
    const loadForksAndCurrent = () => {
        setLoadingForks(true);
        Promise.all([getMinecraftForks(uuid), getCurrentVersion(uuid)])
            .then(([forksData, currentData]) => {
                setForks(forksData.forks);
                if (currentData.current) {
                    setCurrentVersion(currentData.current);
                    if (currentData.current.type) {
                        const type = currentData.current.type;
                        if (forksData.forks[type]) setProvider(type);
                        else if (forksData.forks[type.toLowerCase()]) setProvider(type.toLowerCase());
                        else if (forksData.forks[type.toUpperCase()]) setProvider(type.toUpperCase());
                    }
                }
            })
            .catch((error) => console.error(error))
            .finally(() => setLoadingForks(false));
    };
    const searchVersions = () => {
        setLoading(true);
        clearFlashes('versions');
        getVersions(uuid, provider)
            .then((data) => {
                let allVersions: VersionItem[] = Object.entries(data.versions).map(([id, info]) => ({
                    id,
                    ...info,
                }));
                if (search) {
                    allVersions = allVersions.filter((v) => v.id.toLowerCase().includes(search.toLowerCase()));
                }
                if (filterType !== 'all') {
                    allVersions = allVersions.filter((v) => {
                        if (filterType === 'release') return v.type === 'RELEASE';
                        if (filterType === 'snapshot') return v.type === 'SNAPSHOT';
                        return true;
                    });
                }
                allVersions.sort((a, b) => {
                    const aMatch = a.id.match(/(\d+)(?:\.(\d+))?(?:\.(\d+))?/);
                    const bMatch = b.id.match(/(\d+)(?:\.(\d+))?(?:\.(\d+))?/);
                    if (!aMatch || !bMatch) return 0;
                    const aMajor = parseInt(aMatch[1], 10);
                    const bMajor = parseInt(bMatch[1], 10);
                    if (aMajor !== bMajor) return bMajor - aMajor;
                    const aMinor = aMatch[2] ? parseInt(aMatch[2], 10) : 0;
                    const bMinor = bMatch[2] ? parseInt(bMatch[2], 10) : 0;
                    if (aMinor !== bMinor) return bMinor - aMinor;
                    const aPatch = aMatch[3] ? parseInt(aMatch[3], 10) : 0;
                    const bPatch = bMatch[3] ? parseInt(bMatch[3], 10) : 0;
                    return bPatch - aPatch;
                });
                const total = allVersions.length;
                const totalPages = Math.ceil(total / pageSize);
                const offset = (page - 1) * pageSize;
                const pagedItems = allVersions.slice(offset, offset + pageSize);
                setVersions({
                    items: pagedItems,
                    pagination: {
                        total: total,
                        count: pagedItems.length,
                        perPage: pageSize,
                        currentPage: page,
                        totalPages: totalPages,
                    },
                });
            })
            .catch((error) => {
                clearAndAddHttpError({ key: 'versions', error });
            })
            .finally(() => setLoading(false));
    };
    const loadCurrent = () => {
        getCurrentVersion(uuid)
            .then((data) => {
                if (data.current) setCurrentVersion(data.current);
            })
            .catch(console.error);
    };
    useEffect(() => {
        loadForksAndCurrent();
    }, []);
    useEffect(() => {
        setPage(1);
    }, [provider, pageSize, search, filterType]);
    useEffect(() => {
        const delayDebounceFn = setTimeout(() => {
            searchVersions();
        }, 500);
        return () => clearTimeout(delayDebounceFn);
    }, [page, provider, pageSize, search, filterType]);
    return (
        <ServerContentBlock title={'Minecraft Version Changer'}>
            <FlashMessageRender byKey={'versions'} className={'mb-4'} />
            <div className={'flex flex-col md:flex-row gap-4 items-start'}>
                {/* Sidebar */}
                <div className={'w-full md:w-1/4 sticky top-4'}>
                    <div className={'bg-neutral-700 rounded p-4 shadow-md'}>
                        <div className={'mb-4 relative'}>
                            <Label>Fork</Label>
                            {loadingForks ? (
                                <Spinner size='small' />
                            ) : (
                                <>
                                    <button
                                        type='button'
                                        className='cursor-default bg-neutral-600 border border-neutral-500 text-neutral-200 p-3 w-full rounded text-sm text-left flex items-center justify-between hover:border-neutral-400 focus:outline-none transition-colors duration-150'
                                        onClick={() => {
                                            setForkSelectOpen(!forkSelectOpen);
                                            setForkSearch('');
                                        }}
                                    >
                                        <div className='flex items-center'>
                                            {forks[provider]?.icon ? (
                                                <img
                                                    src={forks[provider].icon}
                                                    alt={provider}
                                                    className='w-6 h-6 mr-2 object-contain'
                                                    onError={(e) => {
                                                        e.currentTarget.style.display = 'none';
                                                    }}
                                                />
                                            ) : null}
                                            <span>{forks[provider]?.name || provider}</span>
                                        </div>
                                        <svg
                                            xmlns='http://www.w3.org/2000/svg'
                                            viewBox='0 0 20 20'
                                            className='w-4 h-4 fill-current text-neutral-200'
                                        >
                                            <path d='M9.293 12.95l.707.707L15.657 8l-1.414-1.414L10 10.828 5.757 6.586 4.343 8z' />
                                        </svg>
                                    </button>
                                    {forkSelectOpen && (
                                        <>
                                            <div
                                                className='fixed inset-0 z-10'
                                                onClick={() => setForkSelectOpen(false)}
                                            />
                                            <div className='absolute z-20 w-full mt-1 bg-neutral-600 border border-neutral-500 rounded shadow-lg max-h-96 overflow-y-auto'>
                                                <div className='p-2 sticky top-0 bg-neutral-600 z-30 border-b border-neutral-500'>
                                                    <input
                                                        type='text'
                                                        className='w-full bg-neutral-700 border border-neutral-500 rounded p-2 text-sm text-neutral-200 focus:outline-none focus:border-neutral-400 placeholder-neutral-500'
                                                        placeholder='Search fork...'
                                                        value={forkSearch}
                                                        onChange={(e) => setForkSearch(e.target.value)}
                                                        autoFocus
                                                        onClick={(e) => e.stopPropagation()}
                                                    />
                                                </div>
                                                {Object.entries(forks)
                                                    .filter(([_, fork]) =>
                                                        fork.name.toLowerCase().includes(forkSearch.toLowerCase())
                                                    )
                                                    .map(([key, fork]) => (
                                                        <div
                                                            key={key}
                                                            className='flex items-center p-3 hover:bg-neutral-500 transition-colors duration-75'
                                                            onClick={() => {
                                                                setProvider(key);
                                                                setForkSelectOpen(false);
                                                            }}
                                                        >
                                                            {fork.icon ? (
                                                                <img
                                                                    src={fork.icon}
                                                                    alt={fork.name}
                                                                    className='w-6 h-6 mr-2 object-contain'
                                                                    onError={(e) => {
                                                                        e.currentTarget.style.display = 'none';
                                                                    }}
                                                                />
                                                            ) : (
                                                                <div className='w-6 h-6 mr-2' />
                                                            )}
                                                            <span className='text-neutral-200 text-sm'>
                                                                {fork.name}
                                                            </span>
                                                        </div>
                                                    ))}
                                                {Object.entries(forks).filter(([_, fork]) =>
                                                    fork.name.toLowerCase().includes(forkSearch.toLowerCase())
                                                ).length === 0 && (
                                                        <div className='p-3 text-neutral-400 text-sm text-center'>
                                                            No forks found.
                                                        </div>
                                                    )}
                                            </div>
                                        </>
                                    )}
                                </>
                            )}
                        </div>
                        <div className={'mb-4'}>
                            <Label>Version Type</Label>
                            <Select value={filterType} onChange={(e) => setFilterType(e.target.value)}>
                                <option value='all'>All Versions</option>
                                <option value='release'>Stable</option>
                                <option value='snapshot'>Snapshot</option>
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
                                placeholder={'Search versions...'}
                            />
                        </div>
                        <div>
                            <Label>Current Version</Label>
                            {!currentVersion ? (
                                <div className={'text-sm text-neutral-300 mt-1'}>Unknown version</div>
                            ) : (
                                <div className={'mt-2'}>
                                    <div
                                        className={
                                            'flex items-center p-3 rounded bg-neutral-600 hover:bg-neutral-500 cursor-default transition-colors'
                                        }
                                    >
                                        {forks[currentVersion.type]?.icon || forks[currentVersion.type.toLowerCase()]?.icon || forks[currentVersion.type.toUpperCase()]?.icon ? (
                                            <img
                                                src={forks[currentVersion.type]?.icon || forks[currentVersion.type.toLowerCase()]?.icon || forks[currentVersion.type.toUpperCase()]?.icon || ''}
                                                className={'w-8 h-8 rounded mr-2 bg-neutral-800 object-contain p-1'}
                                                alt='icon'
                                                onError={(e) => {
                                                    e.currentTarget.style.display = 'none';
                                                }}
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
                                                {currentVersion.type} {currentVersion.version}
                                            </div>
                                            <div className={'text-xs text-neutral-400 truncate'}>
                                                Build: {currentVersion.build}
                                            </div>
                                        </div>
                                    </div>
                                </div>
                            )}
                        </div>
                    </div>
                    <div className={'mt-5 flex items-center justify-center text-sm text-neutral-400'}>
                        Powered by{' '}
                        <a
                            href='https://mcjars.app'
                            target='_blank'
                            rel='noopener noreferrer'
                            className={'flex justify-center items-center hover:text-green-300 cursor-pointer ml-2'}
                        >
                            <img
                                src='https://s3.mcjars.app/icons/vanilla.png'
                                className={'w-4 h-4 mx-1'}
                                alt='MCJars'
                            />
                            MCJars
                        </a>
                    </div>
                </div>
                {/* Main Content */}
                <div className={'w-full md:w-3/4'}>
                    {!versions || (loading && !versions.items?.length) ? (
                        <div className={'w-full flex justify-center mt-8'}>
                            <Spinner size={'large'} />
                        </div>
                    ) : (
                        <Pagination data={versions} onPageSelect={setPage}>
                            {({ items }) => (
                                <div className={'grid grid-cols-1 lg:grid-cols-2 gap-4'}>
                                    {items.map((version) => (
                                        <GreyRowBox
                                            key={version.id}
                                            className={
                                                'hover:bg-neutral-600 transition-colors duration-150 flex flex-col h-full items-start p-4 border border-transparent hover:border-neutral-500 cursor-pointer'
                                            }
                                            onClick={() => setSelectedVersion(version.id)}
                                        >
                                            <div className={'flex items-center w-full'}>
                                                {forks[provider]?.icon ? (
                                                    <img
                                                        src={forks[provider].icon}
                                                        alt={provider}
                                                        className={
                                                            'w-12 h-12 rounded mr-3 object-contain p-1 bg-neutral-800 flex-shrink-0'
                                                        }
                                                        onError={(e) => {
                                                            e.currentTarget.style.display = 'none';
                                                        }}
                                                    />
                                                ) : (
                                                    <div
                                                        className={
                                                            'w-12 h-12 rounded mr-3 bg-neutral-600 flex items-center justify-center text-neutral-400 font-bold text-xs flex-shrink-0'
                                                        }
                                                    >
                                                        VER
                                                    </div>
                                                )}
                                                <div className={'flex-1 min-w-0'}>
                                                    <p className={'text-base text-neutral-100 line-clamp-1'}>
                                                        Version {version.id}
                                                    </p>
                                                    <p
                                                        className={`text-xs line-clamp-1 mt-auto ${version.type === 'SNAPSHOT'
                                                                ? 'text-red-400'
                                                                : 'text-neutral-200'
                                                            }`}
                                                    >
                                                        {version.type} • {version.builds} Builds
                                                    </p>
                                                </div>
                                            </div>
                                        </GreyRowBox>
                                    ))}
                                    {items.length === 0 && (
                                        <div
                                            className={
                                                'col-span-2 text-center text-neutral-400 p-8 bg-neutral-700/50 rounded border-2 border-dashed border-neutral-600'
                                            }
                                        >
                                            No versions found matching your criteria.
                                        </div>
                                    )}
                                </div>
                            )}
                        </Pagination>
                    )}
                </div>
            </div>
            <VersionModal
                version={selectedVersion}
                fork={provider}
                onDismissed={() => setSelectedVersion(null)}
                onInstalled={() => {
                    setSelectedVersion(null);
                    loadCurrent();
                }}
            />
        </ServerContentBlock>
    );
};
