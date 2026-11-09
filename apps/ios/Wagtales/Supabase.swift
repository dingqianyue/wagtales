import Foundation
import Supabase

let supabaseURL = URL(string: "https://jhocepxwuszqicripxwk.supabase.co")!
let supabaseKey = "sb_publishable_H_Bu2rJxBOpp36cGSgspWw_PRaO_Rcp"

let supabase = SupabaseClient(
    supabaseURL: supabaseURL,
    supabaseKey: supabaseKey,
    options: SupabaseClientOptions(
        auth: SupabaseClientOptions.AuthOptions(
            // Opts into Supabase's updated authentication behavior
            // Instantly emits the locally stored user session when the app launches
            emitLocalSessionAsInitialSession: true
        )
    )
)
