// supabase/functions/cleanup-moments/index.ts

import { serve } from "https://deno.land/std@0.203.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

serve(async (_req) => {
  try {
    // -------------------------------
    // ENV
    // -------------------------------
    // Was: a real project URL and a real service_role key hardcoded here,
    // passed as literal string arguments to Deno.env.get() -- which reads
    // an environment variable BY NAME, so this never actually worked, and
    // it committed a live, RLS-bypassing secret (for a different Supabase
    // project than this migration's own "ReServe dev") into the repo's
    // very first commit. Removed; see docs/supabase-migration-status.md
    // for the disclosure. Edge Functions get SUPABASE_URL and
    // SUPABASE_SERVICE_ROLE_KEY injected automatically at runtime by the
    // Supabase platform -- no .env file or secret needs to be set for
    // these two specifically.
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

    if (!supabaseUrl || !serviceRoleKey) {
      return new Response(
        JSON.stringify({ error: "Missing Supabase env vars" }),
        { status: 500 }
      );
    }

    const supabase = createClient(supabaseUrl, serviceRoleKey);

    // -------------------------------
    // TIME LOGIC
    // -------------------------------
    const now = new Date();
    const expiryTime = new Date(now.getTime() - 24 * 60 * 60 * 1000); // 24 hours ago

    // -------------------------------
    // FETCH EXPIRED MOMENTS
    // -------------------------------
    const { data: expiredMoments, error: fetchError } = await supabase
      .from("moments")
      .select("id, media_path")
      .lt("created_at", expiryTime.toISOString());

    if (fetchError) {
      throw fetchError;
    }

    if (!expiredMoments || expiredMoments.length === 0) {
      return new Response(
        JSON.stringify({ message: "No expired moments found" }),
        { status: 200 }
      );
    }

    // -------------------------------
    // DELETE FILES FROM STORAGE
    // -------------------------------
    const filesToDelete = expiredMoments
      .map((m) => m.media_path)
      .filter(Boolean);

    if (filesToDelete.length > 0) {
      const { error: storageError } = await supabase.storage
        .from("moments")
        .remove(filesToDelete);

      if (storageError) {
        throw storageError;
      }
    }

    // -------------------------------
    // DELETE ROWS FROM DB
    // -------------------------------
    const ids = expiredMoments.map((m) => m.id);

    const { error: deleteError } = await supabase
      .from("moments")
      .delete()
      .in("id", ids);

    if (deleteError) {
      throw deleteError;
    }

    // -------------------------------
    // DONE
    // -------------------------------
    return new Response(
      JSON.stringify({
        deleted_moments: ids.length,
        deleted_files: filesToDelete.length,
      }),
      { status: 200 }
    );
  } catch (err) {
    return new Response(
      JSON.stringify({
        error: "Cleanup failed",
        details: String(err),
      }),
      { status: 500 }
    );
  }
});