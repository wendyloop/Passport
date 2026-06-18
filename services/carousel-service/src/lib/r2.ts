import { S3Client, PutObjectCommand } from "@aws-sdk/client-s3";

const R2_ACCOUNT_ID = process.env.R2_ACCOUNT_ID ?? "";
const R2_ACCESS_KEY_ID = process.env.R2_ACCESS_KEY_ID ?? "";
const R2_SECRET_ACCESS_KEY = process.env.R2_SECRET_ACCESS_KEY ?? "";
const R2_BUCKET = process.env.R2_BUCKET ?? "jobtok-carousels";
const R2_PUBLIC_BASE = process.env.R2_PUBLIC_BASE ?? "";

const s3 = new S3Client({
  region: "auto",
  endpoint: `https://${R2_ACCOUNT_ID}.r2.cloudflarestorage.com`,
  credentials: {
    accessKeyId: R2_ACCESS_KEY_ID,
    secretAccessKey: R2_SECRET_ACCESS_KEY,
  },
});

export async function uploadSlides(jobId: string, slides: Buffer[]): Promise<string[]> {
  const urls: string[] = [];

  await Promise.all(
    slides.map(async (buf, i) => {
      const key = `carousels/${jobId}/slide-${i + 1}.png`;
      await s3.send(new PutObjectCommand({
        Bucket: R2_BUCKET,
        Key: key,
        Body: buf,
        ContentType: "image/png",
        CacheControl: "public, max-age=31536000, immutable",
      }));
      urls[i] = `${R2_PUBLIC_BASE}/${key}`;
    })
  );

  return urls;
}
