package wendu.dsbridge;

/**
 * Created by du on 16/12/31.
 */

public interface  CompletionHandler<T> {
    void complete(T retValue);
    /** 插件回调在 JS 实际执行时再次检查文档，普通 basic 回调不使用此入口。 */
    default void completeForDocument(T retValue, String documentId) { complete(retValue); }
    void complete();
    void setProgressData(T value);
}
