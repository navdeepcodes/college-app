// supabase/functions/cleanup-moments/index.ts

import { serve } from "https://deno.land/std@0.203.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

serve(async (_req) => {
  try {
    // -------------------------------
    // ENV
    // -------------------------------
    const supabaseUrl = Deno.env.get("'https://xzohkfdotsnzayiywrie.supabase.co'");
    const serviceRoleKey = Deno.env.get("eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inh6b2hrZmRvdHNuemF5aXl3cmllIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc2NTQyODI2MywiZXhwIjoyMDgxMDA0MjYzfQ.oz83TCmr349cYoaKCWzdaZhVWe7STTy4YPTxW4_GOmc");

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