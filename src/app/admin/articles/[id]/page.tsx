import ArticleEditor from '@/components/admin/ArticleEditor';

export default function EditArticlePage({ params }: { params: { id: string } }) {
  const id = parseInt(params.id, 10);
  return <ArticleEditor articleId={id} />;
}
