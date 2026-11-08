import type { MetadataRoute } from 'next';
export default function sitemap(): MetadataRoute.Sitemap { return [{ url: 'https://bilfred.com', priority: 1 }, { url: 'https://bilfred.com/personvern', priority: 0.3 }]; }
