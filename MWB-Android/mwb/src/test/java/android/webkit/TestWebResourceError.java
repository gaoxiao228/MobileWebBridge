package android.webkit;

/** WebResourceError 构造器为包可见；测试替身只提供系统错误，不替代容器处理逻辑。 */
public final class TestWebResourceError extends WebResourceError {
    @Override public int getErrorCode() { return -2; }
    @Override public CharSequence getDescription() { return "network failed"; }
}
