import {createClient} from 'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2.117.3/+esm';
import {config} from './config.js';
export const client = createClient(config.url,config.publishableKey,{auth:{flowType:'pkce',detectSessionInUrl:false,persistSession:true,autoRefreshToken:true,storageKey:'gatherly-social-auth'}});
