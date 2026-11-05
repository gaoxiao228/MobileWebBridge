# 从子目录复用版本与元数据，仅将文件路径转换为单仓库 Git 检出后的根目录路径。
spec = Pod::Specification.from_file(File.join(__dir__, 'MWB-iOS/MobileWebBridge.podspec'))
%w[source_files public_header_files preserve_paths].each do |attribute|
  paths = Array(spec.attributes_hash.fetch(attribute)).map { |path| "MWB-iOS/#{path}" }
  spec.public_send("#{attribute}=", paths)
end
# 资源 Bundle 的嵌套路径同样按单仓库根目录转换。
spec.resource_bundles = spec.attributes_hash.fetch('resource_bundles').transform_values do |paths|
  Array(paths).map { |path| "MWB-iOS/#{path}" }
end
spec.license = spec.attributes_hash.fetch('license').merge('file' => 'MWB-iOS/LICENSE')
spec
