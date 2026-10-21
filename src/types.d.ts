export {};

declare global {
  interface Window {
    remim: {
      getState: () => Promise<BrowserState>;
      navigate: (address: string) => Promise<void>;
      newTab: (address?: string) => Promise<void>;
      selectTab: (id: string) => Promise<void>;
      closeTab: (id: string) => Promise<void>;
      back: () => Promise<void>;
      forward: () => Promise<void>;
      reload: () => Promise<void>;
      toggleLowMemory: (enabled: boolean) => Promise<void>;
      setChromeHeight: (height: number) => Promise<void>;
      onState: (callback: (state: BrowserState) => void) => () => void;
      onVisit: (callback: (visit: BrowserVisit) => void) => () => void;
      onNotice: (callback: (message: string) => void) => () => void;
    };
  }

  interface BrowserTabState {
    id: string;
    title: string;
    url: string;
    active: boolean;
    frozen: boolean;
    hasSnapshot: boolean;
  }

  interface BrowserState {
    tabs: BrowserTabState[];
    activeTabId: string | null;
    activeUrl: string;
    activeTitle: string;
    activeFrozen: boolean;
    canGoBack: boolean;
    canGoForward: boolean;
    lowMemory: boolean;
    filterEnabled: boolean;
  }

  interface BrowserVisit {
    url: string;
    title: string;
    visitedAt: string;
  }
}

