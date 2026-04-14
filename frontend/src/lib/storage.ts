import { supabase } from "@/lib/supabase";

async function uriToArrayBuffer(uri: string) {
  const response = await fetch(uri);
  return response.arrayBuffer();
}

export async function uploadFileToBucket(params: {
  bucket: "resumes" | "videos" | "avatars";
  fileUri: string;
  contentType?: string;
  path: string;
}) {
  const fileBody = await uriToArrayBuffer(params.fileUri);

  const { data, error } = await supabase.storage
    .from(params.bucket)
    .upload(params.path, fileBody, {
      contentType: params.contentType,
      upsert: true,
    });

  if (error) {
    throw error;
  }

  const { data: publicUrl } = supabase.storage
    .from(params.bucket)
    .getPublicUrl(data.path);

  return {
    path: data.path,
    publicUrl: publicUrl.publicUrl,
  };
}
