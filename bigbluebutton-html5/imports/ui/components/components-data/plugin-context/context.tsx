import React, { createContext, useState } from 'react';
import { ExtensibleArea } from '/imports/ui/components/plugins-engine/extensible-areas/types';
import { PluginsContextType, UserListGraphqlVariables } from './types';

export const PluginsContext = createContext<PluginsContextType>({} as PluginsContextType);

// eslint-disable-next-line @typescript-eslint/no-explicit-any
export const PluginsContextProvider = ({ children, ...props }: any) => {
  const [pluginsExtensibleAreasAggregatedState, setPluginsExtensibleAreasAggregatedState] = useState<ExtensibleArea>(
    {} as ExtensibleArea,
  );
  const [userListGraphqlVariables, setUserListGraphqlVariables] = useState<UserListGraphqlVariables>(
    {} as UserListGraphqlVariables,
  );

  return (
    <PluginsContext.Provider
      value={{
        ...props,
        setPluginsExtensibleAreasAggregatedState,
        pluginsExtensibleAreasAggregatedState,
        userListGraphqlVariables,
        setUserListGraphqlVariables,
      }}
    >
      {children}
    </PluginsContext.Provider>
  );
};